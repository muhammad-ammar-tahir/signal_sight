import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import '../../../data/models/models.dart';
import '../../../data/services/database_service.dart';
import '../../../services/api_service.dart';

class HistoryState extends Equatable {
  final List<ScanSession> sessions;
  final List<Map<String, dynamic>> timeline;
  final int currentIndex;
  final bool isReplaying;
  final bool isLoading;
  final String? error;

  const HistoryState({
    this.sessions = const [],
    this.timeline = const [],
    this.currentIndex = 0,
    this.isReplaying = false,
    this.isLoading = false,
    this.error,
  });

  ScanSession? get currentSession => 
      (sessions.isNotEmpty && currentIndex >= 0 && currentIndex < sessions.length) 
          ? sessions[currentIndex] 
          : null;

  HistoryState copyWith({
    List<ScanSession>? sessions,
    List<Map<String, dynamic>>? timeline,
    int? currentIndex,
    bool? isReplaying,
    bool? isLoading,
    String? error,
  }) => HistoryState(
    sessions: sessions ?? this.sessions,
    timeline: timeline ?? this.timeline,
    currentIndex: currentIndex ?? this.currentIndex,
    isReplaying: isReplaying ?? this.isReplaying,
    isLoading: isLoading ?? this.isLoading,
    error: error,
  );

  @override
  List<Object?> get props => [sessions, timeline, currentIndex, isReplaying, isLoading, error];
}

class HistoryCubit extends Cubit<HistoryState> {
  final DatabaseService _db;
  final ApiService _apiService;
  Timer? _replayTimer;

  HistoryCubit(this._db, this._apiService) : super(const HistoryState());

  Future<void> load() async {
    emit(state.copyWith(isLoading: true, error: null));
    try {
      List<ScanSession> sessions;
      try {
        sessions = await _apiService.getScanHistory(limit: 500);
      } catch (_) {
        sessions = await _db.getScanHistory(limit: 500);
      }

      final sorted = sessions.reversed.toList();
      
      final timeline = sorted.map((s) => {
        'id': s.id,
        'timestamp': s.timestamp.toIso8601String(),
        'networkCount': s.networks.length,
      }).toList();

      if (!isClosed) {
        emit(state.copyWith(
          isLoading: false,
          sessions: sorted,
          timeline: timeline,
          currentIndex: sorted.isNotEmpty ? sorted.length - 1 : 0,
        ));
      }
    } catch (e) {
      if (!isClosed) {
        emit(state.copyWith(isLoading: false, error: e.toString()));
      }
    }
  }

  void seekTo(int index) {
    if (index >= 0 && index < state.sessions.length) {
      emit(state.copyWith(currentIndex: index));
    }
  }

  void startReplay() {
    if (state.sessions.isEmpty) return;
    
    int startIdx = state.currentIndex;
    if (startIdx >= state.sessions.length - 1) {
      startIdx = 0;
    }

    emit(state.copyWith(isReplaying: true, currentIndex: startIdx));

    _replayTimer?.cancel();
    _replayTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (state.currentIndex < state.sessions.length - 1) {
        emit(state.copyWith(currentIndex: state.currentIndex + 1));
      } else {
        stopReplay();
      }
    });
  }

  void stopReplay() {
    _replayTimer?.cancel();
    _replayTimer = null;
    emit(state.copyWith(isReplaying: false));
  }

  @override
  Future<void> close() {
    _replayTimer?.cancel();
    return super.close();
  }
}
