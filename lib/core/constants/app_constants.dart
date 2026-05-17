class AppConstants {
  static const appName = 'SignalSight';
  static const appSubtitle = 'WiFi Signal Intelligence';

  // Method channel names
  static const wifiChannel = 'com.signalsight/wifi';
  static const sensorChannel = 'com.signalsight/sensors';
  static const networkChannel = 'com.signalsight/network';

  // Scan intervals
  static const defaultScanIntervalSec = 5;
  static const minScanIntervalSec = 3;
  static const maxScanIntervalSec = 60;

  // Heatmap
  static const heatmapGridSize = 50;
  static const defaultStrideM = 0.75;

  // AR
  static const pathLossExponent = 2.5;
  static const referenceDistanceM = 1.0;
  static const referenceRssi = -40.0;

  // ITU propagation model
  static const ituN24GHz = 28.0;
  static const ituN5GHz = 31.0;

  // Database
  static const dbName = 'signalsight.db';
  static const dbVersion = 1;

  // SQLite tables
  static const tableScanHistory = 'scan_history';
  static const tableDevices = 'devices';
  static const tableHeatmapSessions = 'heatmap_sessions';
  static const tableHeatmapPoints = 'heatmap_points';

  // Shared prefs keys
  static const prefScanInterval = 'scan_interval';
  static const prefBgScan = 'background_scan';
  static const prefAccentColor = 'accent_color';
  static const prefOnboardingDone = 'onboarding_done';
  static const prefTargetBSSID = 'target_bssid';
  static const prefUserHeight = 'user_height';
  static const prefNewDeviceAlert = 'new_device_alert';
}

class SecurityClassification {
  static const strong = 'Strong';
  static const caution = 'Caution';
  static const weak = 'Weak';
  static const open = 'Open';
}

class ChannelInfo {
  static const channels24GHz = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13];
  static const channels5GHz = [36, 40, 44, 48, 52, 56, 60, 64, 100, 104, 108, 112, 116, 120, 124, 128, 132, 136, 140, 149, 153, 157, 161, 165];

  static double channelFrequency24(int ch) => 2412.0 + (ch - 1) * 5.0;
  static double channelFrequency5(int ch) {
    if (ch <= 64) return 5180.0 + (ch - 36) * 5.0;
    return 5500.0 + (ch - 100) * 5.0;
  }
}
