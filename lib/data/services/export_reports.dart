import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:csv/csv.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:intl/intl.dart';
import '../models/models.dart';

class ExportReports {
  static Future<void> exportCSV(BuildContext context, List<NetworkDevice> devices) async {
    try {
      List<List<dynamic>> rows = [];
      rows.add(["IP Address", "MAC Address", "Hostname", "Vendor", "Category", "Status", "First Seen", "Last Seen", "Label"]);
      
      for (var d in devices) {
        rows.add([
          d.ip,
          d.mac,
          d.hostname ?? '',
          d.vendor,
          d.category,
          d.isOnline ? 'Online' : 'Offline',
          d.firstSeen.toIso8601String(),
          d.lastSeen.toIso8601String(),
          d.label ?? ''
        ]);
      }
      
      String csv = const ListToCsvConverter().convert(rows);
      final dir = await getApplicationDocumentsDirectory();
      final path = '${dir.path}/network_report_${DateTime.now().millisecondsSinceEpoch}.csv';
      final file = File(path);
      await file.writeAsString(csv);
      
      await Share.shareXFiles([XFile(path)], text: 'SignalSight Network Devices CSV');
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Export failed: $e')));
      }
    }
  }

  static Future<void> exportJSON(BuildContext context, List<NetworkDevice> devices) async {
    try {
      final list = devices.map((d) => d.toMap()).toList();
      final jsonStr = const JsonEncoder.withIndent('  ').convert(list);
      
      final dir = await getApplicationDocumentsDirectory();
      final path = '${dir.path}/network_report_${DateTime.now().millisecondsSinceEpoch}.json';
      final file = File(path);
      await file.writeAsString(jsonStr);
      
      await Share.shareXFiles([XFile(path)], text: 'SignalSight Network Devices JSON');
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Export failed: $e')));
      }
    }
  }

  static Future<void> exportPDF(BuildContext context, List<NetworkDevice> devices) async {
    try {
      final pdf = pw.Document();
      final now = DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now());

      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          build: (pw.Context ctx) {
            return [
              pw.Header(
                level: 0,
                child: pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text('SignalSight Network Report', style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold)),
                    pw.Text(now, style: const pw.TextStyle(fontSize: 12)),
                  ]
                )
              ),
              pw.SizedBox(height: 20),
              pw.Text('Total Devices: ${devices.length}', style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 10),
              pw.Table.fromTextArray(
                context: ctx,
                headerDecoration: const pw.BoxDecoration(color: PdfColors.grey300),
                headerHeight: 25,
                cellHeight: 30,
                cellAlignments: {
                  0: pw.Alignment.centerLeft,
                  1: pw.Alignment.centerLeft,
                  2: pw.Alignment.centerLeft,
                  3: pw.Alignment.centerLeft,
                  4: pw.Alignment.center,
                },
                headers: ['IP', 'MAC', 'Hostname / Vendor', 'Category', 'Status'],
                data: devices.map((d) => [
                  d.ip,
                  d.mac,
                  d.hostname?.isNotEmpty == true ? d.hostname : d.vendor,
                  d.category,
                  d.isOnline ? 'Online' : 'Offline'
                ]).toList(),
              ),
            ];
          },
        ),
      );

      final dir = await getApplicationDocumentsDirectory();
      final path = '${dir.path}/network_report_${DateTime.now().millisecondsSinceEpoch}.pdf';
      final file = File(path);
      await file.writeAsBytes(await pdf.save());
      
      await Share.shareXFiles([XFile(path)], text: 'SignalSight Network Devices PDF');
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Export failed: $e')));
      }
    }
  }
}
