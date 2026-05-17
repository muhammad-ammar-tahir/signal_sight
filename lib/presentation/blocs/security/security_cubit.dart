import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import '../../../data/models/models.dart';
import '../../../services/api_service.dart';

// ─── State ────────────────────────────────────────────────────────────────────

class SecurityState extends Equatable {
  final bool isLoading;
  final String? overallStatus;
  final int? score;
  final List<Map<String, dynamic>> advice;
  final String? error;

  const SecurityState({
    this.isLoading = false,
    this.overallStatus,
    this.score,
    this.advice = const [],
    this.error,
  });

  SecurityState copyWith({
    bool? isLoading,
    String? overallStatus,
    int? score,
    List<Map<String, dynamic>>? advice,
    String? error,
  }) {
    return SecurityState(
      isLoading: isLoading ?? this.isLoading,
      overallStatus: overallStatus ?? this.overallStatus,
      score: score ?? this.score,
      advice: advice ?? this.advice,
      error: error,
    );
  }

  @override
  List<Object?> get props => [isLoading, overallStatus, score, advice, error];
}

// ─── Local Classifier ─────────────────────────────────────────────────────────

class _SecurityClassifier {
  static const Map<String, String> _fixInstructions = {
    'OPEN':
        '1. Open your browser and navigate to your router admin (192.168.1.1 or 192.168.0.1).\n'
        '2. Go to Wireless Settings → Security Mode.\n'
        '3. Select WPA3-Personal or WPA2-PSK AES.\n'
        '4. Set a strong 12+ character password.\n'
        '5. Save and reconnect all devices.',
    'WEP':
        '1. Login to your router admin panel.\n'
        '2. Navigate to Wireless → Security.\n'
        '3. Change encryption from WEP to WPA2-AES or WPA3.\n'
        '4. Update your password (avoid dictionary words).\n'
        '5. Reboot the router and reconnect devices.',
    'WPA':
        '1. Access router admin at 192.168.1.1.\n'
        '2. Go to Wireless Security settings.\n'
        '3. Upgrade from WPA-TKIP to WPA2-AES or WPA3.\n'
        '4. Ensure your router firmware is up to date.\n'
        '5. Save changes and reconnect.',
    'WPA2-PSK':
        '1. Use a strong, random 16+ character passphrase.\n'
        '2. Enable WPA3 transition mode if your router supports it.\n'
        '3. Disable WPS (WiFi Protected Setup) to prevent PIN attacks.\n'
        '4. Regularly rotate your WiFi password.',
    'ENTERPRISE':
        '1. Ensure your RADIUS server certificate is up to date.\n'
        '2. Use WPA3-Enterprise if supported.\n'
        '3. Audit RADIUS logs periodically for anomalies.',
    'WPA3':
        '1. Keep router firmware updated.\n'
        '2. No immediate action required – excellent security.',
  };

  static Map<String, dynamic> classify(WifiNetwork network) {
    final cap = network.capabilities.toUpperCase();
    String protocol;
    String riskLevel;
    String recommendation;
    int riskScore; // 0=best, 100=worst

    if (cap.contains('WPA3')) {
      protocol = 'WPA3';
      riskLevel = 'LOW';
      riskScore = 5;
      recommendation = _fixInstructions['WPA3']!;
    } else if (cap.contains('EAP') || cap.contains('ENTERPRISE')) {
      protocol = 'WPA2-Enterprise';
      riskLevel = 'LOW';
      riskScore = 10;
      recommendation = _fixInstructions['ENTERPRISE']!;
    } else if (cap.contains('WPA2') || cap.contains('RSN')) {
      protocol = 'WPA2-PSK';
      riskLevel = 'MEDIUM';
      riskScore = 35;
      recommendation = _fixInstructions['WPA2-PSK']!;
    } else if (cap.contains('WPA')) {
      protocol = 'WPA (Legacy)';
      riskLevel = 'HIGH';
      riskScore = 70;
      recommendation = _fixInstructions['WPA']!;
    } else if (cap.contains('WEP')) {
      protocol = 'WEP (Broken)';
      riskLevel = 'CRITICAL';
      riskScore = 100;
      recommendation = _fixInstructions['WEP']!;
    } else {
      // Empty or ESS-only → Open
      protocol = 'Open / No Encryption';
      riskLevel = 'CRITICAL';
      riskScore = 100;
      recommendation = _fixInstructions['OPEN']!;
    }

    return {
      'bssid': network.bssid,
      'ssid': network.displaySsid,
      'protocol': protocol,
      'risk_level': riskLevel,
      'risk_score': riskScore,
      'recommendation': recommendation,
    };
  }

  static Map<String, dynamic> buildAuditResult(
      List<WifiNetwork> networks) {
    if (networks.isEmpty) {
      return {
        'overall_status': 'NO_DATA',
        'score': 0,
        'advice': <Map<String, dynamic>>[],
      };
    }

    final adviceList = networks.map(classify).toList()
      ..sort((a, b) =>
          (b['risk_score'] as int).compareTo(a['risk_score'] as int));

    // Overall score: 100 = perfect, decreases with risk
    final avgRisk = adviceList.fold<double>(
            0, (sum, a) => sum + (a['risk_score'] as int)) /
        adviceList.length;
    final score = (100 - avgRisk).clamp(0, 100).toInt();

    String status;
    if (score >= 80) {
      status = 'SECURE';
    } else if (score >= 50) {
      status = 'CAUTION';
    } else {
      status = 'CRITICAL';
    }

    return {
      'overall_status': status,
      'score': score,
      'advice': adviceList,
    };
  }
}

// ─── Cubit ────────────────────────────────────────────────────────────────────

class SecurityCubit extends Cubit<SecurityState> {
  final ApiService _apiService;

  // Latest scanned networks – updated externally or via runAuditOnNetworks()
  List<WifiNetwork> _lastNetworks = [];

  SecurityCubit(this._apiService) : super(const SecurityState());

  // ── Run audit on an explicit list (offline, no API required) ──────────────

  Future<void> runAuditOnNetworks(List<WifiNetwork> networks) async {
    emit(state.copyWith(isLoading: true, error: null));
    
    // Simulate a brief delay so the user sees the "Analyzing" state
    await Future.delayed(const Duration(milliseconds: 600));

    if (networks.isEmpty && _lastNetworks.isEmpty) {
      if (!isClosed) {
        emit(state.copyWith(
          isLoading: false,
          overallStatus: 'NO_DATA',
          score: 0,
          advice: [],
          error: null,
        ));
      }
      return;
    }

    _lastNetworks = networks.isNotEmpty ? networks : _lastNetworks;

    try {
      final result = _SecurityClassifier.buildAuditResult(_lastNetworks);
      final adviceList =
          (result['advice'] as List).cast<Map<String, dynamic>>();

      if (!isClosed) {
        emit(state.copyWith(
          isLoading: false,
          overallStatus: result['overall_status'] as String,
          score: result['score'] as int,
          advice: adviceList,
          error: null,
        ));
      }
    } catch (e) {
      if (!isClosed) {
        emit(state.copyWith(
          isLoading: false,
          error: 'Audit failed: ${e.toString()}',
        ));
      }
    }
  }

  Future<void> runAudit() async {
    await runAuditOnNetworks(_lastNetworks);
  }
}
