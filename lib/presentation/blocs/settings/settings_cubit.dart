import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/material.dart';

class SettingsState extends Equatable {
  final int scanInterval;
  final bool bgScan;
  final String notificationPref; // 'silence', 'unknown_only', 'all'
  final String accentColor;
  final double userHeight;
  final String backendUrl;

  const SettingsState({
    this.scanInterval = 15, // Default from AppConstants.defaultScanIntervalSec
    this.bgScan = false,
    this.notificationPref = 'unknown_only',
    this.accentColor = 'cyan',
    this.userHeight = 1.70,
    this.backendUrl = 'http://10.0.2.2:8000/api',
  });

  SettingsState copyWith({
    int? scanInterval,
    bool? bgScan,
    String? notificationPref,
    String? accentColor,
    double? userHeight,
    String? backendUrl,
  }) {
    return SettingsState(
      scanInterval: scanInterval ?? this.scanInterval,
      bgScan: bgScan ?? this.bgScan,
      notificationPref: notificationPref ?? this.notificationPref,
      accentColor: accentColor ?? this.accentColor,
      userHeight: userHeight ?? this.userHeight,
      backendUrl: backendUrl ?? this.backendUrl,
    );
  }

  @override
  List<Object?> get props => [
        scanInterval,
        bgScan,
        notificationPref,
        accentColor,
        userHeight,
        backendUrl,
      ];
}

class SettingsCubit extends Cubit<SettingsState> {
  final dynamic _apiService;

  SettingsCubit(this._apiService) : super(const SettingsState()) {
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final url = prefs.getString('pref_backend_url') ?? 'http://10.0.2.2:8000/api';
    _apiService.baseUrl = url;
    emit(state.copyWith(
      scanInterval: prefs.getInt('pref_scan_interval') ?? 15,
      bgScan: prefs.getBool('pref_bg_scan') ?? false,
      notificationPref: prefs.getString('pref_notification_pref') ?? 'unknown_only',
      accentColor: prefs.getString('pref_accent_color') ?? 'cyan',
      userHeight: prefs.getDouble('pref_user_height') ?? 1.70,
      backendUrl: url,
    ));
  }

  Future<void> updateScanInterval(int interval) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('pref_scan_interval', interval);
    emit(state.copyWith(scanInterval: interval));
  }

  Future<void> updateBgScan(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('pref_bg_scan', enabled);
    emit(state.copyWith(bgScan: enabled));
  }

  Future<void> updateNotificationPref(String pref) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('pref_notification_pref', pref);
    emit(state.copyWith(notificationPref: pref));
  }

  Future<void> updateAccentColor(String colorName) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('pref_accent_color', colorName);
    emit(state.copyWith(accentColor: colorName));
  }

  Future<void> updateUserHeight(double height) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('pref_user_height', height);
    emit(state.copyWith(userHeight: height));
  }

  Future<void> updateBackendUrl(String url) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('pref_backend_url', url);
    _apiService.baseUrl = url;
    emit(state.copyWith(backendUrl: url));
  }

  Future<void> clearCache(dynamic dbService) async {
    final db = await dbService.database;
    await db.delete('scan_history');
    await db.delete('devices');
    await db.delete('heatmap_sessions');
    await db.delete('heatmap_points');
  }

  Future<String> exportHistory(dynamic dbService) async {
    final history = await dbService.getScanHistory(limit: 1000);
    final sb = StringBuffer();
    sb.writeln('Timestamp,SSID,BSSID,RSSI,Channel,Security,Vendor');
    for (var session in history) {
      for (var net in session.networks) {
        sb.writeln('${session.timestamp.toIso8601String()},"${net.ssid}","${net.bssid}",${net.rssi},${net.channel},"${net.security}","${net.vendor}"');
      }
    }
    return sb.toString();
  }
}
