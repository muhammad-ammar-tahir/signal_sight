import 'dart:convert';
import 'package:flutter/services.dart';

class OuiLookup {
  static final Map<String, String> _lookupMap = {};
  static bool _isLoaded = false;

  /// Load OUI data from assets/data/oui.csv if it exists, otherwise use hardcoded map
  static Future<void> load() async {
    if (_isLoaded) return;
    
    // First populate with hardcoded common vendors (fallback)
    _populateHardcoded();
    
    try {
      final csvString = await rootBundle.loadString('assets/data/oui.csv');
      final lines = const LineSplitter().convert(csvString);
      for (final line in lines) {
        if (line.isEmpty || line.startsWith('OUI')) continue; // Skip header
        final parts = line.split(',');
        if (parts.length >= 2) {
          final prefix = parts[0].replaceAll(':', '').replaceAll('-', '').toUpperCase();
          final vendor = parts[1].trim();
          if (prefix.length >= 6) {
            _lookupMap[prefix.substring(0, 6)] = vendor;
          }
        }
      }
    } catch (_) {
      // Failed to load CSV, hardcoded map will be used
    }
    
    _isLoaded = true;
  }

  /// Get vendor name for a given MAC address (e.g. "00:1A:2B:3C:4D:5E")
  static String getVendor(String macAddress) {
    if (macAddress.isEmpty) return "Unknown";
    final prefix = macAddress.replaceAll(':', '').replaceAll('-', '').toUpperCase();
    if (prefix.length >= 6) {
      final oui = prefix.substring(0, 6);
      return _lookupMap[oui] ?? _inferVendorFromMac(oui);
    }
    return "Unknown";
  }
  
  static String _inferVendorFromMac(String oui) {
    // If not in map, return unknown
    return "Unknown";
  }

  static void _populateHardcoded() {
    final Map<String, String> common = {
      // Apple
      '000393': 'Apple', '000A27': 'Apple', '000D93': 'Apple', '0010FA': 'Apple',
      '001124': 'Apple', '001451': 'Apple', '0016CB': 'Apple', '0017F2': 'Apple',
      '0019E3': 'Apple', '001B63': 'Apple', '001C63': 'Apple', '001D4F': 'Apple',
      '001E52': 'Apple', '001EC2': 'Apple', '001F5C': 'Apple', '0021E9': 'Apple',
      '002312': 'Apple', '002332': 'Apple', '0023DF': 'Apple', '002436': 'Apple',
      '002500': 'Apple', '0025BC': 'Apple', '002608': 'Apple', '0026B0': 'Apple',
      '0026BB': 'Apple', '003EE1': 'Apple', '0050E4': 'Apple', '00F569': 'Apple',
      '040CCE': 'Apple', '101C0C': 'Apple', '14109F': 'Apple', '18AF61': 'Apple',
      '24AB81': 'Apple', '28CFE9': 'Apple', '34C059': 'Apple', '38484C': 'Apple',
      '406C8F': 'Apple', '440010': 'Apple', '4CD577': 'Apple', '508F4C': 'Apple',
      '58B035': 'Apple', '60F81D': 'Apple', '64B9E8': 'Apple', '68A86D': 'Apple',
      '784F43': 'Apple', '7C6D62': 'Apple', '80EA96': 'Apple', '88C663': 'Apple',
      '90B931': 'Apple', '98460A': 'Apple', 'A4B197': 'Apple', 'A82066': 'Apple',
      'B88D12': 'Apple', 'BC52B7': 'Apple', 'C8B5B7': 'Apple', 'CC08E0': 'Apple',
      'D0A637': 'Apple', 'D49A20': 'Apple', 'DC2B61': 'Apple', 'E0F847': 'Apple',
      'F0D1A9': 'Apple', 'F81EDF': 'Apple', 'FCFC48': 'Apple', '8C8590': 'Apple',
      '0017AB': 'Nintendo', '0009BF': 'Nintendo', '00191D': 'Nintendo', '001E35': 'Nintendo',
      '0021BD': 'Nintendo', '00224C': 'Nintendo', '0022D7': 'Nintendo', '0023CC': 'Nintendo',
      '00241E': 'Nintendo', '002444': 'Nintendo', '0025A0': 'Nintendo', '002659': 'Nintendo',
      '002709': 'Nintendo', '0403D6': 'Nintendo', '2CF7F1': 'Nintendo', '40D32D': 'Nintendo',
      '582F40': 'Nintendo', '7CBB8A': 'Nintendo', '885BFA': 'Nintendo', '94EBC1': 'Nintendo',
      '98B6E9': 'Nintendo', 'A4C0E1': 'Nintendo', 'B8AE6E': 'Nintendo', 'CC9E00': 'Nintendo',
      'D86BF7': 'Nintendo', 'E0E751': 'Nintendo', 'E4D332': 'Nintendo',
      
      // Samsung
      '000278': 'Samsung', '0007AB': 'Samsung', '000918': 'Samsung', '000D09': 'Samsung',
      '000E8A': 'Samsung', '001247': 'Samsung', '001599': 'Samsung', '001632': 'Samsung',
      '00166B': 'Samsung', '0017D5': 'Samsung', '0018FA': 'Samsung', '001A8A': 'Samsung',
      '001C43': 'Samsung', '001D25': 'Samsung', '001E7A': 'Samsung', '001F2A': 'Samsung',
      '002119': 'Samsung', '00214C': 'Samsung', '0021B1': 'Samsung', '00233A': 'Samsung',
      '002399': 'Samsung', '0023D6': 'Samsung', '002454': 'Samsung', '0024E4': 'Samsung',
      '002566': 'Samsung', '002637': 'Samsung', '08D42B': 'Samsung', '0C1420': 'Samsung',
      '103047': 'Samsung', '14109F': 'Samsung', '18227E': 'Samsung', '1CC1D7': 'Samsung',
      '20D390': 'Samsung', '241FA0': 'Samsung', '28987B': 'Samsung', '2C0E3D': 'Samsung',
      '301966': 'Samsung', '342387': 'Samsung', '380A94': 'Samsung', '3C8BFE': 'Samsung',
      '40331A': 'Samsung', '444CE6': 'Samsung', '4844F7': 'Samsung', '4CC3D9': 'Samsung',
      '503275': 'Samsung', '54880E': 'Samsung', '581FD3': 'Samsung', '5CAAFD': 'Samsung',
      '60128B': 'Samsung', '641C67': 'Samsung', '680571': 'Samsung', '6C2F8A': 'Samsung',
      '702A84': 'Samsung', '7445CE': 'Samsung', '784B87': 'Samsung', '7C1CB4': 'Samsung',
      '8018A7': 'Samsung', '8425DB': 'Samsung', '88329B': 'Samsung', '8C7712': 'Samsung',
      '90187C': 'Samsung', '94350A': 'Samsung', '980C82': 'Samsung', '9C0298': 'Samsung',
      'A00BBA': 'Samsung', 'A4880A': 'Samsung', 'A80600': 'Samsung', 'AC3613': 'Samsung',
      'B0C090': 'Samsung', 'B46293': 'Samsung', 'B8BA46': 'Samsung', 'BC20A4': 'Samsung',
      'C0847A': 'Samsung', 'C44202': 'Samsung', 'C81451': 'Samsung', 'CC07AB': 'Samsung',
      'D01A1E': 'Samsung', 'D487D8': 'Samsung', 'D8E56D': 'Samsung', 'DC7144': 'Samsung',
      'E09971': 'Samsung', 'E4121D': 'Samsung', 'E81132': 'Samsung', 'EC1F72': 'Samsung',
      'F025B7': 'Samsung', 'F47B5E': 'Samsung', 'F8042E': 'Samsung', 'FC1999': 'Samsung',
      
      // Google
      '001A11': 'Google', '3C5A20': 'Google', '546009': 'Google', 'A47733': 'Google',
      'E0FCE8': 'Google', 'F48C50': 'Google', '00259C': 'Cisco', '001A2B': 'Cisco',
      
      // Cisco
      '00000C': 'Cisco', '000142': 'Cisco', '000143': 'Cisco', '000196': 'Cisco',
      '0001C7': 'Cisco', '0001C9': 'Cisco', '000216': 'Cisco', '000217': 'Cisco',
      '0002B9': 'Cisco', '0002FC': 'Cisco', '0003E3': 'Cisco', '0004DD': 'Cisco',
      
      // Amazon
      '00FCA8': 'Amazon', '0403D6': 'Amazon', '0C473D': 'Amazon', '18742E': 'Amazon',
      '34D270': 'Amazon', '38F73D': 'Amazon', '40B4CD': 'Amazon', '44650D': 'Amazon',
      '488F5A': 'Amazon', '50DCE7': 'Amazon', '6837E9': 'Amazon', '6854FD': 'Amazon',
      '74C246': 'Amazon', '84D6D0': 'Amazon', '8871E5': 'Amazon', 'A002DC': 'Amazon',
      'B47C9C': 'Amazon', 'C05627': 'Amazon', 'F0038C': 'Amazon', 'F0272D': 'Amazon',
      'F4A42A': 'Amazon', 'FCA183': 'Amazon',
      
      // Netgear
      '00095B': 'Netgear', '000FB5': 'Netgear', '00146C': 'Netgear', '00184D': 'Netgear',
      '001B2F': 'Netgear', '001E2A': 'Netgear', '00223F': 'Netgear', '0023CD': 'Netgear',
      '0024B2': 'Netgear', '0026F2': 'Netgear', '08BD43': 'Netgear', '100000': 'Netgear',
      
      // TP-Link
      '000A25': 'TP-Link', '001D0F': 'TP-Link', '002131': 'TP-Link', '0023CF': 'TP-Link',
      '002586': 'TP-Link', '0C8063': 'TP-Link', '107B44': 'TP-Link', '14CC20': 'TP-Link',
      '18A6F7': 'TP-Link', '30B5C2': 'TP-Link', '34E894': 'TP-Link', '503EAA': 'TP-Link',
      
      // Lenovo
      '0012FE': 'Lenovo', '00508D': 'Lenovo', '482C6A': 'Lenovo', '503EAA': 'Lenovo',
      
      // Dell
      '00065B': 'Dell', '000874': 'Dell', '000BDB': 'Dell', '000F1F': 'Dell',
      '001143': 'Dell', '00123F': 'Dell', '001372': 'Dell', '001422': 'Dell',
      
      // HP
      '0008C7': 'HP', '000E7F': 'HP', '000F20': 'HP', '00110A': 'HP',
      '001279': 'HP', '001321': 'HP', '001438': 'HP', '001560': 'HP',
      
      // Sony
      '00014A': 'Sony', '0005C1': 'Sony', '000A40': 'Sony', '000E07': 'Sony',
      '00100C': 'Sony', '001128': 'Sony', '0013A9': 'Sony', '0015B7': 'Sony',
      
      // LG
      '0005C9': 'LG', '00196D': 'LG', '001C62': 'LG', '001E8C': 'LG',
      '0022A1': 'LG', '0024B1': 'LG', '00262F': 'LG', '00E091': 'LG',
      
      // Intel
      '0002B3': 'Intel', '000347': 'Intel', '000423': 'Intel', '000E0C': 'Intel',
      '0013E8': 'Intel', '001517': 'Intel', '001B21': 'Intel', '001CC0': 'Intel',
    };
    
    _lookupMap.addAll(common);
  }
}
