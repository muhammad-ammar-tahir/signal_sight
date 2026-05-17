import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import '../../../services/api_service.dart';
import '../../../data/models/models.dart';
import '../../../core/utils/algorithms.dart';

// ─── State ────────────────────────────────────────────────────────────────────

class ChannelState extends Equatable {
  final bool isLoading;
  final String band;
  final int? bestChannel;
  final Map<int, double> congestionScores;
  final List<Map<String, dynamic>> channelDetails;
  final String reasoning;
  final String? error;

  const ChannelState({
    this.isLoading = false,
    this.band = '2.4GHz',
    this.bestChannel,
    this.congestionScores = const {},
    this.channelDetails = const [],
    this.reasoning = '',
    this.error,
  });

  ChannelState copyWith({
    bool? isLoading,
    String? band,
    int? bestChannel,
    Map<int, double>? congestionScores,
    List<Map<String, dynamic>>? channelDetails,
    String? reasoning,
    String? error,
  }) {
    return ChannelState(
      isLoading: isLoading ?? this.isLoading,
      band: band ?? this.band,
      bestChannel: bestChannel ?? this.bestChannel,
      congestionScores: congestionScores ?? this.congestionScores,
      channelDetails: channelDetails ?? this.channelDetails,
      reasoning: reasoning ?? this.reasoning,
      error: error,
    );
  }

  @override
  List<Object?> get props => [
        isLoading,
        band,
        bestChannel,
        congestionScores,
        channelDetails,
        reasoning,
        error,
      ];
}

// ─── Cubit ────────────────────────────────────────────────────────────────────

class ChannelCubit extends Cubit<ChannelState> {
  final ApiService _apiService;

  ChannelCubit(this._apiService) : super(const ChannelState());

  // ── Fetch from backend, fall back to local scan data ─────────────────────

  Future<void> fetchRecommendations({
    String band = '2.4GHz',
    List<WifiNetwork>? localNetworks,
  }) async {
    emit(state.copyWith(isLoading: true, band: band, error: null));
    try {
      final result = await _apiService.getChannelRecommendation(band);

      final scores = <int, double>{};
      final rawScores = result['congestion_scores'] as Map<String, dynamic>;
      rawScores.forEach((key, value) {
        scores[int.parse(key)] = (value as num).toDouble();
      });

      final details = (result['channel_details'] as List<dynamic>)
          .cast<Map<String, dynamic>>();

      if (!isClosed) {
        emit(state.copyWith(
          isLoading: false,
          bestChannel: result['best_channel'] as int,
          congestionScores: scores,
          channelDetails: details,
          reasoning: result['reasoning'] as String? ?? '',
          error: null,
        ));
      }
    } catch (_) {
      // Backend unavailable → compute locally from scanned networks
      if (localNetworks != null && localNetworks.isNotEmpty) {
        _computeLocally(band: band, networks: localNetworks);
      } else {
        if (!isClosed) {
          emit(state.copyWith(
            isLoading: false,
            error: 'Backend offline. Scan networks to get local recommendation.',
          ));
        }
      }
    }
  }

  // ── Local-only computation (called from ScanCubit after every scan) ───────

  void computeFromNetworks({
    required List<WifiNetwork> networks,
    String band = '2.4GHz',
  }) {
    _computeLocally(band: band, networks: networks);
  }

  void _computeLocally({
    required String band,
    required List<WifiNetwork> networks,
  }) {
    final is5GHz = band == '5GHz';
    final aps = networks
        .where((n) => is5GHz ? n.is5GHz : !n.is5GHz)
        .map((n) => (channel: n.channel, rssi: n.rssi))
        .toList();

    final congestion = ChannelUtils.computeCongestion(aps, is5GHz: is5GHz);
    final bestList = ChannelUtils.bestChannels(congestion);
    final bestCh = bestList.isNotEmpty ? bestList.first.channel : null;

    // Build channel details list
    final details = congestion.entries
        .map((e) => {
              'channel': e.key,
              'congestion_score': e.value,
              'ap_count': aps.where((a) => a.channel == e.key).length,
            })
        .toList()
      ..sort((a, b) =>
          (a['congestion_score'] as double)
              .compareTo(b['congestion_score'] as double));

    String reasoning = '';
    if (bestCh != null) {
      final apCount = aps.where((a) => a.channel == bestCh).length;
      reasoning = 'Channel $bestCh has the lowest congestion'
          '${apCount > 0 ? ' ($apCount AP(s) detected)' : ''}. '
          'Switch your router to this channel for optimal performance.';
    }

    if (!isClosed) {
      emit(state.copyWith(
        isLoading: false,
        band: band,
        bestChannel: bestCh,
        congestionScores: congestion,
        channelDetails: details,
        reasoning: reasoning,
        error: null,
      ));
    }
  }

  void toggleBand({List<WifiNetwork>? localNetworks}) {
    final newBand = state.band == '2.4GHz' ? '5GHz' : '2.4GHz';
    fetchRecommendations(band: newBand, localNetworks: localNetworks);
  }
}
