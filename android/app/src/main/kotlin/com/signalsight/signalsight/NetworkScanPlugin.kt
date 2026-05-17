package com.signalsight.signalsight

import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.net.nsd.NsdManager
import android.net.nsd.NsdServiceInfo
import android.net.wifi.WifiManager
import android.os.Build
import android.text.format.Formatter
import androidx.core.app.NotificationCompat
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.*
import java.net.DatagramPacket
import java.net.DatagramSocket
import java.net.InetAddress
import java.net.InetSocketAddress
import java.net.Socket
import java.util.concurrent.ConcurrentHashMap

/**
 * NetworkScanPlugin – unrooted-safe device discovery on Android 11+.
 *
 * Channel layout:
 *   MethodChannel  "com.signalsight/network"          → getSubnet, scanDevices (starts scan),
 *                                                         stopScan, discoverSSDP, scanPorts,
 *                                                         pingDevice, showNotification
 *   EventChannel   "com.signalsight/network_stream"   → streams Map<String,Any> device updates
 *                                                         while scan is running
 *
 * Discovery methods (parallel):
 *   1. NsdManager mDNS – _http._tcp, _https._tcp, _printer._tcp, _googlecast._tcp, _airplay._tcp
 *   2. SSDP M-SEARCH UDP 239.255.255.250:1900
 *   3. TCP connect probe on common ports for every host in /24 subnet
 */
class NetworkScanPlugin(
    private val context: Context,
    private val binaryMessenger: io.flutter.plugin.common.BinaryMessenger
) : MethodChannel.MethodCallHandler {

    private val coroutineScope = CoroutineScope(Dispatchers.IO + SupervisorJob())
    private var scanJob: Job? = null

    // EventChannel sink – receives real-time device updates
    private var eventSink: EventChannel.EventSink? = null

    // Deduplication: ip -> device map collected during a scan
    private val discovered = ConcurrentHashMap<String, MutableMap<String, Any>>()

    init {
        EventChannel(binaryMessenger, "com.signalsight/network_stream")
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    eventSink = events
                }
                override fun onCancel(arguments: Any?) {
                    eventSink = null
                }
            })
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "getSubnet" -> result.success(getLocalSubnet())

            "scanDevices" -> {
                // Cancel any running scan
                scanJob?.cancel()
                discovered.clear()
                scanJob = coroutineScope.launch {
                    try {
                        val subnet = getLocalSubnet()
                        if (subnet == null) {
                            withContext(Dispatchers.Main) {
                                result.error("NO_SUBNET", "Not connected to WiFi", null)
                            }
                            return@launch
                        }

                        // Return immediately so Flutter doesn't time-out the method call;
                        // results arrive via EventChannel
                        withContext(Dispatchers.Main) { result.success(null) }

                        // Run three discovery methods in parallel
                        val mdnsJob   = launch { runMdnsDiscovery() }
                        val ssdpJob   = launch { runSsdpDiscovery(subnet) }
                        val tcpJob    = launch { runTcpPortScan(subnet) }

                        listOf(mdnsJob, ssdpJob, tcpJob).joinAll()

                        // Signal completion
                        withContext(Dispatchers.Main) {
                            eventSink?.endOfStream()
                        }
                    } catch (e: CancellationException) {
                        // Normal stop
                    } catch (e: Exception) {
                        withContext(Dispatchers.Main) {
                            eventSink?.error("SCAN_ERROR", e.message, null)
                        }
                    }
                }
            }

            "stopScan" -> {
                scanJob?.cancel()
                scanJob = null
                result.success(null)
            }

            "discoverSSDP" -> {
                coroutineScope.launch {
                    try {
                        val subnet = getLocalSubnet() ?: "192.168.1"
                        val results = collectSsdpResults(subnet)
                        withContext(Dispatchers.Main) { result.success(results) }
                    } catch (e: Exception) {
                        withContext(Dispatchers.Main) { result.error("SSDP_ERROR", e.message, null) }
                    }
                }
            }

            "scanPorts" -> {
                val ip = call.argument<String>("ip")
                if (ip == null) { result.error("INVALID_ARGS", "IP required", null); return }
                coroutineScope.launch {
                    try {
                        val ports = scanCommonPorts(ip)
                        withContext(Dispatchers.Main) { result.success(ports) }
                    } catch (e: Exception) {
                        withContext(Dispatchers.Main) { result.error("PORT_ERROR", e.message, null) }
                    }
                }
            }

            "pingDevice" -> {
                val ip = call.argument<String>("ip")
                if (ip == null) { result.success(false); return }
                coroutineScope.launch {
                    val alive = isHostReachable(ip)
                    withContext(Dispatchers.Main) { result.success(alive) }
                }
            }

            "showNotification" -> {
                val title   = call.argument<String>("title") ?: ""
                val body    = call.argument<String>("body") ?: ""
                showNotification(title, body)
                result.success(true)
            }

            else -> result.notImplemented()
        }
    }

    // ── Subnet helper ─────────────────────────────────────────────────────────

    private fun getLocalSubnet(): String? {
        return try {
            val wm = context.applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
            @Suppress("DEPRECATION")
            val ip = wm.connectionInfo.ipAddress
            if (ip == 0) return null
            @Suppress("DEPRECATION")
            val ipStr = Formatter.formatIpAddress(ip)
            val parts = ipStr.split(".")
            if (parts.size == 4) "${parts[0]}.${parts[1]}.${parts[2]}" else null
        } catch (_: Exception) { null }
    }

    // ── Method 1: NsdManager mDNS ────────────────────────────────────────────

    private suspend fun runMdnsDiscovery() = withContext(Dispatchers.IO) {
        val serviceTypes = listOf(
            "_http._tcp.",
            "_https._tcp.",
            "_printer._tcp.",
            "_googlecast._tcp.",
            "_airplay._tcp.",
            "_smb._tcp.",
            "_ftp._tcp.",
            "_ssh._tcp.",
        )

        val nsdManager = context.getSystemService(Context.NSD_SERVICE) as NsdManager
        val pendingResolves = ConcurrentHashMap<String, NsdServiceInfo>()
        val completedJobs = mutableListOf<Job>()

        for (serviceType in serviceTypes) {
            if (!isActive) break
            val latch = kotlinx.coroutines.channels.Channel<Unit>(1)

            val listener = object : NsdManager.DiscoveryListener {
                override fun onStartDiscoveryFailed(st: String, err: Int) { latch.trySend(Unit) }
                override fun onStopDiscoveryFailed(st: String, err: Int) {}
                override fun onDiscoveryStarted(st: String) {}
                override fun onDiscoveryStopped(st: String) { latch.trySend(Unit) }
                override fun onServiceFound(info: NsdServiceInfo) {
                    // Resolve to get host/port
                    nsdManager.resolveService(info, object : NsdManager.ResolveListener {
                        override fun onResolveFailed(si: NsdServiceInfo, err: Int) {}
                        override fun onServiceResolved(si: NsdServiceInfo) {
                            val host = si.host ?: return
                            val ip = host.hostAddress ?: return
                            mergeDevice(ip, si.serviceName ?: "", serviceType.trimEnd('.'), "mDNS")
                        }
                    })
                }
                override fun onServiceLost(info: NsdServiceInfo) {}
            }

            try {
                nsdManager.discoverServices(serviceType, NsdManager.PROTOCOL_DNS_SD, listener)
                // Listen for 2 seconds per service type
                val job = coroutineScope.launch {
                    delay(2000)
                    try { nsdManager.stopServiceDiscovery(listener) } catch (_: Exception) {}
                }
                completedJobs.add(job)
            } catch (_: Exception) {
                latch.trySend(Unit)
            }
        }

        // Wait for all stop timers
        completedJobs.joinAll()
    }

    // ── Method 2: SSDP M-SEARCH ──────────────────────────────────────────────

    private suspend fun runSsdpDiscovery(subnet: String) = withContext(Dispatchers.IO) {
        var socket: DatagramSocket? = null
        try {
            socket = DatagramSocket()
            socket.soTimeout = 3000
            socket.broadcast = true

            val address = InetAddress.getByName("239.255.255.250")
            val request = buildString {
                append("M-SEARCH * HTTP/1.1\r\n")
                append("HOST: 239.255.255.250:1900\r\n")
                append("MAN: \"ssdp:discover\"\r\n")
                append("MX: 2\r\n")
                append("ST: ssdp:all\r\n\r\n")
            }
            val data = request.toByteArray(Charsets.UTF_8)
            socket.send(DatagramPacket(data, data.size, address, 1900))

            val deadline = System.currentTimeMillis() + 3000L
            while (isActive && System.currentTimeMillis() < deadline) {
                try {
                    val buf = ByteArray(2048)
                    val pkt = DatagramPacket(buf, buf.size)
                    socket.receive(pkt)

                    val response = String(pkt.data, 0, pkt.length, Charsets.UTF_8)
                    val ip = pkt.address?.hostAddress ?: continue
                    var server = ""; var st = ""

                    response.lines().forEach { line ->
                        when {
                            line.startsWith("SERVER:", ignoreCase = true) ->
                                server = line.substringAfter(":").trim()
                            line.startsWith("ST:", ignoreCase = true) ->
                                st = line.substringAfter(":").trim()
                        }
                    }

                    val svcName = when {
                        server.isNotEmpty() -> server
                        st.isNotEmpty()     -> st
                        else                -> "SSDP"
                    }
                    mergeDevice(ip, svcName, "SSDP", "SSDP")
                } catch (_: java.net.SocketTimeoutException) { break }
                  catch (_: Exception) {}
            }
        } catch (_: Exception) {
        } finally {
            socket?.close()
        }
    }

    private suspend fun collectSsdpResults(subnet: String): List<Map<String, String>> {
        val results = mutableListOf<Map<String, String>>()
        var socket: DatagramSocket? = null
        try {
            socket = DatagramSocket()
            socket.soTimeout = 2000
            val address = InetAddress.getByName("239.255.255.250")
            val request = "M-SEARCH * HTTP/1.1\r\nHOST: 239.255.255.250:1900\r\nMAN: \"ssdp:discover\"\r\nMX: 2\r\nST: ssdp:all\r\n\r\n"
            val data = request.toByteArray()
            socket.send(DatagramPacket(data, data.size, address, 1900))

            val deadline = System.currentTimeMillis() + 2000L
            while (System.currentTimeMillis() < deadline) {
                try {
                    val buf = ByteArray(2048)
                    val pkt = DatagramPacket(buf, buf.size)
                    socket.receive(pkt)
                    val resp = String(pkt.data, 0, pkt.length)
                    val ip = pkt.address?.hostAddress ?: continue
                    var server = ""; var st = ""
                    resp.lines().forEach { line ->
                        if (line.startsWith("SERVER:", ignoreCase = true)) server = line.substringAfter(":").trim()
                        if (line.startsWith("ST:", ignoreCase = true)) st = line.substringAfter(":").trim()
                    }
                    if (ip.isNotEmpty()) results.add(mapOf("ip" to ip, "server" to server, "st" to st))
                } catch (_: java.net.SocketTimeoutException) { break }
                  catch (_: Exception) {}
            }
        } catch (_: Exception) {
        } finally { socket?.close() }
        return results
    }

    // ── Method 3: TCP port probe across /24 subnet ───────────────────────────

    private val COMMON_PORTS = listOf(80, 443, 8080, 22, 8000, 21, 8443, 5000, 3000, 9000)

    private suspend fun runTcpPortScan(subnet: String) = withContext(Dispatchers.IO) {
        // Sweep all 254 hosts in parallel batches of 32
        val hosts = (1..254).toList()
        for (chunk in hosts.chunked(32)) {
            if (!isActive) break
            val jobs = chunk.map { last ->
                async(Dispatchers.IO) {
                    if (!isActive) return@async
                    val ip = "$subnet.$last"
                    // Quick reachability probe first (port 80, 443, 22 – 200ms)
                    val openPort = probeFirstOpen(ip, COMMON_PORTS, timeoutMs = 200)
                    if (openPort != null) {
                        val hostname = tryReverseDns(ip)
                        mergeDevice(ip, hostname ?: ip, "TCP:$openPort", "TCP")
                    }
                }
            }
            jobs.awaitAll()
        }
    }

    private fun probeFirstOpen(ip: String, ports: List<Int>, timeoutMs: Int): Int? {
        for (port in ports) {
            var sock: Socket? = null
            try {
                sock = Socket()
                sock.connect(InetSocketAddress(ip, port), timeoutMs)
                return port
            } catch (_: Exception) {
            } finally {
                try { sock?.close() } catch (_: Exception) {}
            }
        }
        return null
    }

    private fun tryReverseDns(ip: String): String? {
        return try {
            val addr = InetAddress.getByName(ip)
            val canonical = addr.canonicalHostName
            if (canonical == ip) null else canonical
        } catch (_: Exception) { null }
    }

    // ── Merge & emit ─────────────────────────────────────────────────────────

    private fun mergeDevice(ip: String, name: String, serviceType: String, source: String) {
        val isNew = !discovered.containsKey(ip)
        val entry = discovered.getOrPut(ip) {
            mutableMapOf(
                "ip"          to ip,
                "mac"         to derivePseudoMac(ip),
                "vendor"      to "Unknown",
                "deviceName"  to (name.ifEmpty { ip }),
                "serviceType" to serviceType,
                "deviceType"  to guessDeviceType(name, serviceType),
                "source"      to source,
            )
        }

        // Enrich if we got a better name
        if (name.isNotEmpty() && name != ip) {
            entry["deviceName"] = name
        }
        if (serviceType.isNotEmpty()) {
            val existing = entry["serviceType"] as? String ?: ""
            if (!existing.contains(serviceType)) {
                entry["serviceType"] = if (existing.isEmpty()) serviceType else "$existing, $serviceType"
            }
        }

        // Send update to Flutter
        val snapshot = HashMap(entry)
        android.os.Handler(android.os.Looper.getMainLooper()).post {
            eventSink?.success(snapshot)
        }
    }

    /** Generate a stable pseudo-MAC from the IP when real MAC is unavailable. */
    private fun derivePseudoMac(ip: String): String {
        val octets = ip.split(".").mapNotNull { it.toIntOrNull() }
        if (octets.size != 4) return "00:00:00:00:00:00"
        return "02:00:%02x:%02x:%02x:%02x".format(octets[0], octets[1], octets[2], octets[3])
    }

    private fun guessDeviceType(name: String, service: String): String {
        val n = name.lowercase()
        val s = service.lowercase()
        return when {
            s.contains("googlecast") || s.contains("chromecast") || n.contains("chromecast") -> "Media Streamer"
            s.contains("airplay") || n.contains("apple") || n.contains("iphone") || n.contains("ipad") -> "Phone/Tablet"
            s.contains("printer") || n.contains("print")  -> "Printer"
            s.contains("smb") || n.contains("nas") || n.contains("synology") || n.contains("qnap") -> "NAS/Storage"
            n.contains("router") || n.contains("gateway") || n.contains("tp-link") ||
                n.contains("netgear") || n.contains("asus") && s.contains("http") -> "Networking"
            s.contains("ssh") || n.contains("laptop") || n.contains("pc") || n.contains("desktop") -> "Laptop/PC"
            else -> "IoT/Other"
        }
    }

    // ── Port scan (on-demand for device detail) ───────────────────────────────

    private suspend fun scanCommonPorts(ip: String): List<Int> = coroutineScope {
        val ports = listOf(21, 22, 23, 53, 80, 111, 135, 139, 443, 445, 554,
                           3306, 3389, 5000, 5900, 8000, 8080, 8443, 9000)
        ports.map { port ->
            async(Dispatchers.IO) {
                var sock: Socket? = null
                try {
                    sock = Socket()
                    sock.connect(InetSocketAddress(ip, port), 300)
                    port
                } catch (_: Exception) { null }
                finally { try { sock?.close() } catch (_: Exception) {} }
            }
        }.awaitAll().filterNotNull().sorted()
    }

    // ── Ping / reachability ───────────────────────────────────────────────────

    private suspend fun isHostReachable(ip: String): Boolean = withContext(Dispatchers.IO) {
        // Try ICMP first, fall back to TCP port 80
        try {
            val addr = InetAddress.getByName(ip)
            if (addr.isReachable(800)) return@withContext true
        } catch (_: Exception) {}
        probeFirstOpen(ip, listOf(80, 443, 22, 8080), 500) != null
    }

    // ── Notification ─────────────────────────────────────────────────────────

    private fun showNotification(title: String, body: String) {
        val channelId = "network_alerts"
        val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            nm.createNotificationChannel(
                NotificationChannel(channelId, "Network Alerts", NotificationManager.IMPORTANCE_HIGH)
            )
        }
        val iconId = context.resources.getIdentifier("ic_launcher", "mipmap", context.packageName)
            .takeIf { it != 0 } ?: android.R.drawable.ic_dialog_info
        nm.notify(
            (System.currentTimeMillis() % 100_000).toInt(),
            NotificationCompat.Builder(context, channelId)
                .setSmallIcon(iconId)
                .setContentTitle(title)
                .setContentText(body)
                .setPriority(NotificationCompat.PRIORITY_HIGH)
                .setAutoCancel(true)
                .build()
        )
    }
}
