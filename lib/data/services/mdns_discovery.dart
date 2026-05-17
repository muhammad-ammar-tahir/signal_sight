/// MDNSDiscovery – Dart-side stub.
///
/// The multicast_dns package uses RawDatagramSocket.bind(reusePort: true)
/// which is NOT supported on many Android kernels (e.g. Infinix X6528,
/// Android 11) and causes an immediate OS exception, crashing the scan.
///
/// mDNS discovery is handled entirely by the native NsdManager inside
/// NetworkScanPlugin.kt, so this Dart class is intentionally a no-op.
/// Keeping the class signature avoids import errors in device_cubit.dart.
class MDNSDiscovery {
  /// Returns an empty map – all mDNS work is done natively via NsdManager.
  static Future<Map<String, List<String>>> scanServices({
    Duration timeout = const Duration(seconds: 4),
  }) async {
    return const {};
  }
}
