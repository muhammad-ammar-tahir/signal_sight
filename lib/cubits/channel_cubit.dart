import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import '../../services/api_service.dart';

abstract class ChannelState extends Equatable {
  const ChannelState();
  @override
  List<Object?> get props => [];
}

class ChannelInitial extends ChannelState {}
class ChannelLoading extends ChannelState {}

class ChannelLoaded extends ChannelState {
  final Map<String, dynamic> recommendation;
  final Map<int, double> graphData;
  const ChannelLoaded(this.recommendation, this.graphData);
  @override
  List<Object?> get props => [recommendation, graphData];
}

class ChannelError extends ChannelState {
  final String message;
  const ChannelError(this.message);
  @override
  List<Object?> get props => [message];
}

class ChannelCubit extends Cubit<ChannelState> {
  final ApiService _apiService;

  ChannelCubit(this._apiService) : super(ChannelInitial());

  Future<void> analyzeChannels({String band = "2.4GHz"}) async {
    emit(ChannelLoading());
    try {
      final result = await _apiService.getChannelRecommendation(band);
      final scores = Map<int, double>.from((result['congestion_scores'] as Map).map(
          (k, v) => MapEntry(int.parse(k.toString()), (v as num).toDouble())
      ));
      emit(ChannelLoaded(result, scores));
    } catch (e) {
      emit(ChannelError(e.toString()));
    }
  }

  void getRecommendation() => analyzeChannels();
}
