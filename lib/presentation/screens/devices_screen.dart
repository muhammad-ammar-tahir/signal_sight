import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shimmer/shimmer.dart';
import 'package:intl/intl.dart';
import '../blocs/device/device_cubit.dart';
import '../widgets/common_widgets.dart';
import '../../core/theme/app_theme.dart';
import '../../data/models/models.dart';
import '../../data/services/export_reports.dart';
import '../../data/services/port_scanner.dart';

class DevicesScreen extends StatefulWidget {
  const DevicesScreen({super.key});

  @override
  State<DevicesScreen> createState() => _DevicesScreenState();
}

class _DevicesScreenState extends State<DevicesScreen> with SingleTickerProviderStateMixin {
  late AnimationController _pulseCtrl;
  bool _autoRefresh = false;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(vsync: this, duration: const Duration(seconds: 2))..repeat(reverse: true);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<DeviceCubit>().loadFromDb();
    });
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    super.dispose();
  }

  void _showLabelDialog(BuildContext context, NetworkDevice device, bool markKnown) {
    final tc = TextEditingController(text: device.label ?? device.hostname ?? device.vendor);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.card,
        title: Text(markKnown ? 'Mark as Known' : 'Edit Label', style: const TextStyle(color: Colors.white)),
        content: TextField(
          controller: tc,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            labelText: 'Device Nickname',
            labelStyle: TextStyle(color: AppColors.textMuted),
            enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: AppColors.cardBorder)),
            focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: AppColors.cyan)),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel', style: TextStyle(color: AppColors.textMuted))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.cyan, foregroundColor: Colors.white),
            onPressed: () {
              context.read<DeviceCubit>().updateDeviceLabel(device.mac, tc.text.trim(), markKnown);
              Navigator.pop(ctx);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _showExportMenu(BuildContext context, List<NetworkDevice> devices) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.background,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16.0),
              child: Text('Export Network Report', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
            ),
            ListTile(
              leading: const Icon(Icons.table_chart, color: AppColors.emerald),
              title: const Text('Export as CSV', style: TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.pop(ctx);
                ExportReports.exportCSV(context, devices);
              },
            ),
            ListTile(
              leading: const Icon(Icons.data_object, color: AppColors.amber),
              title: const Text('Export as JSON', style: TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.pop(ctx);
                ExportReports.exportJSON(context, devices);
              },
            ),
            ListTile(
              leading: const Icon(Icons.picture_as_pdf, color: AppColors.rose),
              title: const Text('Export as PDF', style: TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.pop(ctx);
                ExportReports.exportPDF(context, devices);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showDeviceDetails(BuildContext context, NetworkDevice device) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.background,
      isScrollControlled: true,
      builder: (ctx) => _DeviceDetailSheet(device: device),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Device Discovery'),
        actions: [
          Row(
            children: [
              const Text('Auto', style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
              Switch(
                value: _autoRefresh,
                activeColor: AppColors.cyan,
                onChanged: (val) {
                  setState(() => _autoRefresh = val);
                  context.read<DeviceCubit>().toggleAutoRefresh(val);
                },
              ),
            ],
          ),
          BlocBuilder<DeviceCubit, DeviceState>(
            builder: (context, state) {
              if (state is DeviceLoaded) {
                return IconButton(
                  icon: const Icon(Icons.download_rounded, color: AppColors.cyan),
                  onPressed: () => _showExportMenu(context, state.devices),
                );
              }
              return const SizedBox.shrink();
            },
          ),
        ],
      ),
      floatingActionButton: BlocBuilder<DeviceCubit, DeviceState>(
        builder: (context, state) {
          final isScanning = state is DeviceLoading || state is DeviceScanning;
          return AnimatedBuilder(
            animation: _pulseCtrl,
            builder: (context, child) {
              return Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.cyan.withOpacity(isScanning ? 0.4 * _pulseCtrl.value : 0.2),
                      blurRadius: isScanning ? 24 : 12,
                      spreadRadius: isScanning ? 4 : 0,
                    ),
                  ],
                ),
                child: FloatingActionButton(
                  backgroundColor: isScanning ? AppColors.amber : AppColors.cyan,
                  foregroundColor: AppColors.background,
                  onPressed: isScanning ? null : () => context.read<DeviceCubit>().scan(),
                  child: isScanning ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(color: AppColors.background, strokeWidth: 2.5)) : const Icon(Icons.radar_rounded, size: 26),
                ),
              );
            },
          );
        },
      ),
      body: BlocConsumer<DeviceCubit, DeviceState>(
        listenWhen: (prev, curr) => curr is DeviceLoaded && curr.warning != null,
        listener: (context, state) {
          if (state is DeviceLoaded && state.warning != null) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text(state.warning!, overflow: TextOverflow.ellipsis, maxLines: 2),
              backgroundColor: AppColors.amberDim,
              behavior: SnackBarBehavior.floating,
              margin: const EdgeInsets.all(16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10), side: const BorderSide(color: AppColors.amber)),
              duration: const Duration(seconds: 4),
            ));
          }
        },
        builder: (context, state) {
          if (state is DeviceInitial) return _EmptyState(onScan: () => context.read<DeviceCubit>().scan());
          if (state is DeviceLoading) return _ShimmerList();

          // ── Live scanning: show growing list with scanning badge ──
          if (state is DeviceScanning) {
            return Column(
              children: [
                _ScanningBanner(count: state.devices.length),
                Expanded(
                  child: state.devices.isEmpty
                      ? _ShimmerList()
                      : _DeviceList(
                          devices: state.devices,
                          onRefresh: () => context.read<DeviceCubit>().scan(),
                          onMarkKnown: (d) => _showLabelDialog(context, d, true),
                          onIgnore: (d) => context.read<DeviceCubit>().markUnknown(d.mac),
                          onDetails: (d) => _showDeviceDetails(context, d),
                        ),
                ),
              ],
            );
          }

          if (state is DeviceLoaded) {
            return Column(
              children: [
                if (state.unknownDevices.isNotEmpty)
                  Container(
                    width: double.infinity,
                    color: AppColors.roseDim,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    child: Row(
                      children: [
                        const Icon(Icons.warning_amber_rounded, color: AppColors.rose),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('${state.unknownDevices.length} Unrecognized device(s)', style: const TextStyle(color: AppColors.rose, fontWeight: FontWeight.bold, fontSize: 13)),
                              const SizedBox(height: 2),
                              const Text('Swipe left on a device to mark it as known.', style: TextStyle(color: AppColors.rose, fontSize: 11)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                Expanded(
                  child: _DeviceList(
                    devices: state.devices,
                    onRefresh: () => context.read<DeviceCubit>().scan(),
                    onMarkKnown: (d) => _showLabelDialog(context, d, true),
                    onIgnore: (d) => context.read<DeviceCubit>().markUnknown(d.mac),
                    onDetails: (d) => _showDeviceDetails(context, d),
                  ),
                ),
              ],
            );
          }
          if (state is DeviceEmpty) {
            return RefreshIndicator(
              color: AppColors.cyan,
              backgroundColor: AppColors.card,
              onRefresh: () => context.read<DeviceCubit>().scan(),
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                child: SizedBox(height: MediaQuery.of(context).size.height * 0.65, child: _NoDevicesFound(onScan: () => context.read<DeviceCubit>().scan())),
              ),
            );
          }
          if (state is DeviceError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: GlassCard(
                  glowing: true,
                  glowColor: AppColors.rose,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.error_outline_rounded, color: AppColors.rose, size: 48),
                      const SizedBox(height: 12),
                      Text('Scan Failed', style: Theme.of(context).textTheme.headlineMedium),
                      const SizedBox(height: 8),
                      Text(state.message, style: const TextStyle(color: AppColors.textSecondary, fontSize: 13), textAlign: TextAlign.center),
                      const SizedBox(height: 20),
                      GradientButton(label: 'Retry Scan', icon: Icons.refresh_rounded, onPressed: () => context.read<DeviceCubit>().scan()),
                    ],
                  ),
                ),
              ),
            );
          }
          return const SizedBox.shrink();
        },
      ),
    );
  }
}

class _DeviceDetailSheet extends StatefulWidget {
  final NetworkDevice device;
  const _DeviceDetailSheet({required this.device});

  @override
  State<_DeviceDetailSheet> createState() => _DeviceDetailSheetState();
}

class _DeviceDetailSheetState extends State<_DeviceDetailSheet> {
  bool _isScanningPorts = false;
  List<int>? _openPorts;

  Future<void> _scanPorts() async {
    setState(() => _isScanningPorts = true);
    final ports = await PortScanner.scanPorts(widget.device.ip);
    setState(() {
      _openPorts = ports;
      _isScanningPorts = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      height: MediaQuery.of(context).size.height * 0.75,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Device Analytics', style: Theme.of(context).textTheme.headlineSmall),
              IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
            ],
          ),
          const Divider(color: AppColors.cardBorder),
          ListTile(
            title: const Text('Hostname', style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
            subtitle: Text(widget.device.hostname?.isNotEmpty == true ? widget.device.hostname! : 'Unknown Hostname', style: const TextStyle(color: Colors.white, fontSize: 16)),
          ),
          ListTile(
            title: const Text('Category & Vendor', style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
            subtitle: Text('${widget.device.category} / ${widget.device.vendor}', style: const TextStyle(color: Colors.white, fontSize: 16)),
          ),
          if (widget.device.mdnsServices.isNotEmpty || widget.device.ssdpServices.isNotEmpty)
            ListTile(
              title: const Text('Zero-Conf Services', style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
              subtitle: Text([...widget.device.mdnsServices, ...widget.device.ssdpServices].join('\n'), style: const TextStyle(color: AppColors.emerald, fontSize: 14)),
            ),
          const SizedBox(height: 16),
          const Text('Advanced Port Scan', style: TextStyle(color: AppColors.amber, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          const Text('Scan common TCP ports to detect running services. This may take a few seconds.', style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              style: OutlinedButton.styleFrom(foregroundColor: AppColors.amber, side: const BorderSide(color: AppColors.amber)),
              onPressed: _isScanningPorts ? null : _scanPorts,
              child: _isScanningPorts ? const CircularProgressIndicator(strokeWidth: 2, color: AppColors.amber) : const Text('Run TCP Port Scan'),
            ),
          ),
          const SizedBox(height: 16),
          if (_openPorts != null)
            Expanded(
              child: Container(
                decoration: BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.circular(8)),
                child: _openPorts!.isEmpty 
                  ? const Center(child: Text('No common ports open', style: TextStyle(color: AppColors.emerald)))
                  : ListView.builder(
                      itemCount: _openPorts!.length,
                      itemBuilder: (ctx, i) {
                        final port = _openPorts![i];
                        final service = PortScanner.getServiceName(port);
                        return ListTile(
                          leading: const Icon(Icons.lock_open_rounded, color: AppColors.rose),
                          title: Text('Port $port open', style: const TextStyle(color: Colors.white)),
                          subtitle: Text('Possible service: $service', style: const TextStyle(color: AppColors.rose)),
                        );
                      },
                    ),
              ),
            ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final VoidCallback onScan;
  const _EmptyState({required this.onScan});

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: const BoxDecoration(color: AppColors.cyanDim, shape: BoxShape.circle),
            child: const Icon(Icons.radar_rounded, color: AppColors.cyan, size: 64),
          ).animate(onPlay: (c) => c.repeat()).shimmer(duration: 2000.ms, color: AppColors.cyan),
          const SizedBox(height: 24),
          Text('Discover Network Devices', style: Theme.of(context).textTheme.headlineLarge, textAlign: TextAlign.center),
          const SizedBox(height: 10),
          const Text('Scan your local network to find all\nconnected devices using ARP & ICMP.', style: TextStyle(color: AppColors.textSecondary, height: 1.5), textAlign: TextAlign.center),
          const SizedBox(height: 28),
          GradientButton(label: 'Start Scan', icon: Icons.radar_rounded, onPressed: onScan),
        ],
      ),
    ),
  );
}

class _NoDevicesFound extends StatelessWidget {
  final VoidCallback onScan;
  const _NoDevicesFound({required this.onScan});

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.wifi_off_rounded, color: AppColors.textMuted, size: 64),
        const SizedBox(height: 16),
        Text('No Devices Found', style: Theme.of(context).textTheme.headlineMedium!.copyWith(color: AppColors.textMuted)),
        const SizedBox(height: 24),
        GradientButton(label: 'Scan Again', icon: Icons.search_rounded, onPressed: onScan),
      ],
    ),
  );
}

// Live scan progress banner ─────────────────────────────────────────────────
class _ScanningBanner extends StatelessWidget {
  final int count;
  const _ScanningBanner({required this.count});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: const BoxDecoration(
        color: AppColors.card,
        border: Border(bottom: BorderSide(color: AppColors.cardBorder)),
      ),
      child: Row(
        children: [
          const ScanDot(active: true),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Scanning… $count device${count == 1 ? '' : 's'} found',
              style: const TextStyle(
                color: AppColors.cyan,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: AppColors.cyan,
            ),
          ),
        ],
      ),
    );
  }
}

class _ShimmerList extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: const BoxDecoration(color: AppColors.card, border: Border(bottom: BorderSide(color: AppColors.cardBorder))),
          child: const Row(
            children: [
              ScanDot(active: true),
              SizedBox(width: 10),
              Text('Scanning subnet…', style: TextStyle(color: AppColors.cyan, fontSize: 13, fontWeight: FontWeight.w600)),
              Spacer(),
              Text('ARP + DNS + SSDP', style: TextStyle(color: AppColors.textMuted, fontSize: 11)),
            ],
          ),
        ),
        Expanded(
          child: Shimmer.fromColors(
            baseColor: AppColors.card,
            highlightColor: AppColors.surface,
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              itemCount: 7,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (_, __) => Container(height: 90, decoration: BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.circular(16))),
            ),
          ),
        ),
      ],
    );
  }
}

class _DeviceList extends StatelessWidget {
  final List<NetworkDevice> devices;
  final Future<void> Function() onRefresh;
  final void Function(NetworkDevice) onMarkKnown;
  final void Function(NetworkDevice) onIgnore;
  final void Function(NetworkDevice) onDetails;

  const _DeviceList({
    required this.devices,
    required this.onRefresh,
    required this.onMarkKnown,
    required this.onIgnore,
    required this.onDetails,
  });

  @override
  Widget build(BuildContext context) {
    final newDevices = devices.where((d) => !d.isKnown).toList();
    final knownDevices = devices.where((d) => d.isKnown).toList();

    return RefreshIndicator(
      color: AppColors.cyan,
      backgroundColor: AppColors.card,
      onRefresh: onRefresh,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
        children: [
          Row(children: [
            _SummaryChip(label: 'Total', value: '${devices.length}', color: AppColors.cyan),
            const SizedBox(width: 10),
            _SummaryChip(label: 'Unknown', value: '${newDevices.length}', color: newDevices.isEmpty ? AppColors.textMuted : AppColors.rose),
            const SizedBox(width: 10),
            _SummaryChip(label: 'Known', value: '${knownDevices.length}', color: AppColors.emerald),
          ]).animate().fadeIn(duration: 300.ms),

          const SizedBox(height: 16),

          if (newDevices.isNotEmpty) ...[
            SectionHeader(
              title: 'Unknown Devices',
              trailing: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(color: AppColors.roseDim, borderRadius: BorderRadius.circular(6)),
                child: const Text('⚠ Alert', style: TextStyle(color: AppColors.rose, fontSize: 11, fontWeight: FontWeight.w700)),
              ),
            ),
            const SizedBox(height: 10),
            ...newDevices.asMap().entries.map((e) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _DeviceCard(device: e.value, index: e.key, onMarkKnown: () => onMarkKnown(e.value), onIgnore: () => onIgnore(e.value), onTap: () => onDetails(e.value)),
            )),
            const SizedBox(height: 16),
          ],

          if (knownDevices.isNotEmpty) ...[
            const SectionHeader(title: 'Known Devices'),
            const SizedBox(height: 10),
            ...knownDevices.asMap().entries.map((e) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _DeviceCard(device: e.value, index: e.key, onMarkKnown: () => onMarkKnown(e.value), onIgnore: () => onIgnore(e.value), onTap: () => onDetails(e.value)),
            )),
          ],

          if (devices.isEmpty)
            const Center(child: Padding(padding: EdgeInsets.all(32), child: Text('Pull down to scan', style: TextStyle(color: AppColors.textMuted)))),
        ],
      ),
    );
  }
}

class _SummaryChip extends StatelessWidget {
  final String label, value;
  final Color color;
  const _SummaryChip({required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) => Expanded(
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(color: color.withOpacity(0.08), borderRadius: BorderRadius.circular(12), border: Border.all(color: color.withOpacity(0.2))),
      child: Column(children: [
        Text(value, style: TextStyle(color: color, fontSize: 22, fontWeight: FontWeight.w800)),
        Text(label, style: const TextStyle(color: AppColors.textMuted, fontSize: 11)),
      ]),
    ),
  );
}

class _DeviceCard extends StatelessWidget {
  final NetworkDevice device;
  final int index;
  final VoidCallback onMarkKnown;
  final VoidCallback onIgnore;
  final VoidCallback onTap;

  const _DeviceCard({required this.device, required this.index, required this.onMarkKnown, required this.onIgnore, required this.onTap});

  IconData get _icon {
    switch (device.category) {
      case 'Phone/Tablet': return Icons.smartphone_rounded;
      case 'Laptop/PC': return Icons.laptop_rounded;
      case 'Networking': return Icons.router_rounded;
      case 'Smart TV': 
      case 'TV/Console': return Icons.tv_rounded;
      case 'Smart Home/IoT': return Icons.home_repair_service_rounded;
      case 'Printer': return Icons.print_rounded;
      case 'Media Streamer': return Icons.cast_rounded;
      default: return Icons.devices_other_rounded;
    }
  }

  Color get _typeColor {
    switch (device.category) {
      case 'Networking': return AppColors.emerald;
      case 'Phone/Tablet': return AppColors.cyan;
      case 'Laptop/PC': return AppColors.purple;
      case 'Smart TV': 
      case 'TV/Console': return AppColors.amber;
      case 'Smart Home/IoT': return AppColors.rose;
      case 'Printer': return Colors.teal;
      case 'Media Streamer': return Colors.blueAccent;
      default: return AppColors.textSecondary;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isNew = !device.isKnown;
    final accentColor = isNew ? AppColors.rose : _typeColor;
    
    final duration = DateTime.now().difference(device.firstSeen);
    String connTime = duration.inHours > 0 ? '${duration.inHours}h ${duration.inMinutes % 60}m' : '${duration.inMinutes}m';
    if (duration.inMinutes == 0) connTime = 'Just now';

    return Dismissible(
      key: Key(device.mac),
      background: Container(
        padding: const EdgeInsets.only(left: 20),
        alignment: Alignment.centerLeft,
        decoration: BoxDecoration(color: AppColors.emerald, borderRadius: BorderRadius.circular(16)),
        child: const Row(children: [Icon(Icons.edit, color: Colors.white), SizedBox(width: 8), Text('Edit / Mark Known', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold))]),
      ),
      secondaryBackground: Container(
        padding: const EdgeInsets.only(right: 20),
        alignment: Alignment.centerRight,
        decoration: BoxDecoration(color: AppColors.textMuted, borderRadius: BorderRadius.circular(16)),
        child: const Row(mainAxisAlignment: MainAxisAlignment.end, children: [Text('Ignore/Block', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)), SizedBox(width: 8), Icon(Icons.block, color: Colors.white)]),
      ),
      confirmDismiss: (direction) async {
        if (direction == DismissDirection.startToEnd) {
          onMarkKnown();
          return false;
        } else {
          onIgnore();
          return false;
        }
      },
      child: GestureDetector(
        onTap: onTap,
        child: GlassCard(
          borderColor: isNew ? AppColors.rose.withOpacity(0.5) : null,
          glowing: isNew,
          glowColor: AppColors.rose,
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(color: accentColor.withOpacity(0.12), borderRadius: BorderRadius.circular(12), border: Border.all(color: accentColor.withOpacity(0.25))),
                child: Icon(_icon, color: accentColor, size: 24),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Expanded(
                        child: Text(
                          device.label ?? (device.hostname?.isNotEmpty == true ? device.hostname! : device.vendor),
                          style: Theme.of(context).textTheme.bodyLarge!.copyWith(fontWeight: FontWeight.w700),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (isNew)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(color: AppColors.roseDim, borderRadius: BorderRadius.circular(4)),
                          child: const Text('UNKNOWN', style: TextStyle(color: AppColors.rose, fontSize: 9, fontWeight: FontWeight.w800, letterSpacing: 0.8)),
                        ),
                    ]),
                    const SizedBox(height: 3),
                    Row(children: [
                      Icon(Icons.circle, color: device.isOnline ? AppColors.emerald : AppColors.textMuted, size: 7),
                      const SizedBox(width: 5),
                      Text(device.ip, style: GoogleFonts.sourceCodePro(color: AppColors.cyan, fontSize: 12, fontWeight: FontWeight.w600)),
                    ]),
                    const SizedBox(height: 2),
                    Text(device.mac, style: GoogleFonts.sourceCodePro(color: AppColors.textMuted, fontSize: 10, letterSpacing: 0.5)),
                    const SizedBox(height: 4),
                    Row(children: [
                      const Icon(Icons.access_time_rounded, color: AppColors.textMuted, size: 11),
                      const SizedBox(width: 4),
                      Text('Conn $connTime', style: Theme.of(context).textTheme.bodySmall),
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(color: _typeColor.withOpacity(0.1), borderRadius: BorderRadius.circular(4)),
                        child: Text(device.category.toUpperCase(), style: TextStyle(color: _typeColor, fontSize: 9, fontWeight: FontWeight.w700, letterSpacing: 0.5)),
                      ),
                    ]),
                  ],
                ),
              ),
            ],
          ),
        ).animate(delay: (index * 50).ms).fadeIn(duration: 300.ms).slideX(begin: 0.06, end: 0),
      ),
    );
  }
}
