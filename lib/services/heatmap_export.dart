import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../presentation/blocs/heatmap/heatmap_cubit.dart';

class HeatmapExport {
  /// Save the heatmap widget as a PNG image and share it
  static Future<void> saveHeatmapImage(BuildContext context, GlobalKey repaintKey) async {
    try {
      final boundary = repaintKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) throw Exception("Could not find render boundary");
      
      final image = await boundary.toImage(pixelRatio: 2.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) throw Exception("Failed to convert image to bytes");
      
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/heatmap_${DateTime.now().millisecondsSinceEpoch}.png');
      await file.writeAsBytes(byteData.buffer.asUint8List());
      
      await Share.shareXFiles([XFile(file.path)], text: 'SignalSight Heatmap Image');
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Image export failed: $e')));
      }
    }
  }

  /// Export points as CSV
  static Future<void> exportSessionCSV(BuildContext context, HeatmapState state) async {
    try {
      if (state.points.isEmpty) throw Exception("No points to export");
      
      final StringBuffer sb = StringBuffer();
      sb.writeln("x,y,rssi,timestamp");
      for (final p in state.points) {
        sb.writeln("${p.x},${p.y},${p.rssi},${p.timestamp.toIso8601String()}");
      }
      
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/heatmap_data_${DateTime.now().millisecondsSinceEpoch}.csv');
      await file.writeAsString(sb.toString());
      
      await Share.shareXFiles([XFile(file.path)], text: 'SignalSight CSV Data');
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('CSV export failed: $e')));
      }
    }
  }

  /// Export session metadata and points as JSON
  static Future<void> exportSessionJSON(BuildContext context, HeatmapState state) async {
    try {
      if (state.points.isEmpty) throw Exception("No points to export");
      
      final Map<String, dynamic> data = {
        'session_id': state.sessionId,
        'target_bssid': state.targetBssid,
        'timestamp': DateTime.now().toIso8601String(),
        'min_rssi': state.minRssi,
        'max_rssi': state.maxRssi,
        'area_sqm': state.areaSqM,
        'calibration_rssi': state.calibrationRssiAtOneMeter,
        'points': state.points.map((p) => p.toMap()).toList(),
      };
      
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/heatmap_session_${DateTime.now().millisecondsSinceEpoch}.json');
      await file.writeAsString(jsonEncode(data));
      
      await Share.shareXFiles([XFile(file.path)], text: 'SignalSight JSON Data');
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('JSON export failed: $e')));
      }
    }
  }
}
