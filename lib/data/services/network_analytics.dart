import 'device_db.dart';
import '../models/models.dart';

class NetworkAnalytics {
  final DeviceDb _db;
  
  NetworkAnalytics(this._db);
  
  /// Get total devices detected today
  Future<int> getTodayTotal() async {
    final devices = await _db.loadAllDevices();
    return devices.length;
  }
  
  /// Get number of unknown devices
  Future<int> getUnknownCount() async {
    final devices = await _db.loadAllDevices();
    return devices.where((d) => !d.isKnown).length;
  }
  
  /// Get historical counts for chart (last 7 days)
  Future<List<Map<String, dynamic>>> getHistoricalData() async {
    return await _db.getDailyCounts(7);
  }
  
  /// Evaluate and assign better classification category
  static String categorizeDevice(String vendor, String? hostname, List<String> mdns, List<String> ssdp) {
    final v = vendor.toLowerCase();
    final h = (hostname ?? '').toLowerCase();
    final mStr = mdns.join(' ').toLowerCase();
    final sStr = ssdp.join(' ').toLowerCase();
    
    // Check Smart TV / Media
    if (v.contains('samsung') && (mStr.contains('tv') || sStr.contains('mediarenderer') || h.contains('tv'))) return 'Smart TV';
    if (v.contains('lg') || h.contains('webos') || h.contains('tv')) return 'Smart TV';
    if (h.contains('bravia') || v.contains('sony')) return 'Smart TV';
    if (h.contains('chromecast') || mStr.contains('googlecast') || h.contains('apple-tv') || mStr.contains('airplay')) return 'Media Streamer';
    
    // Check Printers
    if (v.contains('hp') && (mStr.contains('printer') || h.contains('printer') || h.contains('laserjet'))) return 'Printer';
    if (mStr.contains('printer') || mStr.contains('ipp') || mStr.contains('pdl-datastream')) return 'Printer';
    
    // Check Phones / Tablets
    if (v.contains('apple') && (h.contains('iphone') || h.contains('ipad'))) return 'Phone/Tablet';
    if (v.contains('samsung') || v.contains('google') || v.contains('oneplus') || v.contains('xiaomi')) return 'Phone/Tablet';
    if (mStr.contains('mobiledevice')) return 'Phone/Tablet';
    
    // Check Laptops / PCs
    if (v.contains('dell') || v.contains('lenovo') || v.contains('acer') || v.contains('asus') || v.contains('intel')) return 'Laptop/PC';
    if (v.contains('apple') && h.contains('macbook')) return 'Laptop/PC';
    
    // Check Networking
    if (v.contains('cisco') || v.contains('netgear') || v.contains('tp-link') || v.contains('d-link') || v.contains('ubiquiti') || v.contains('arris')) return 'Networking';
    
    // Check Smart Home / IoT
    if (v.contains('amazon') || h.contains('echo') || sStr.contains('wemo') || mStr.contains('hue') || v.contains('philips') || v.contains('ring') || v.contains('nest')) return 'Smart Home/IoT';
    
    return 'Unknown';
  }
}
