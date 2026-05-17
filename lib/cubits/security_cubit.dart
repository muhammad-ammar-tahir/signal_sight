import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import '../../services/api_service.dart';

abstract class SecurityState extends Equatable {
  const SecurityState();
  @override
  List<Object?> get props => [];
}

class SecurityInitial extends SecurityState {}
class SecurityLoading extends SecurityState {}

class SecurityLoaded extends SecurityState {
  final Map<String, dynamic> auditResults;
  const SecurityLoaded(this.auditResults);
  @override
  List<Object?> get props => [auditResults];
}

class SecurityError extends SecurityState {
  final String message;
  const SecurityError(this.message);
  @override
  List<Object?> get props => [message];
}

class SecurityCubit extends Cubit<SecurityState> {
  final ApiService _apiService;

  SecurityCubit(this._apiService) : super(SecurityInitial());

  Future<void> runAudit() async {
    emit(SecurityLoading());
    try {
      final results = await _apiService.getSecurityAudit();
      emit(SecurityLoaded(results));
    } catch (e) {
      emit(SecurityError(e.toString()));
    }
  }

  void getDetailedAdvice() {
    if (state is SecurityLoaded) {
      // Re-trigger state to update UI if needed
      emit(SecurityLoaded((state as SecurityLoaded).auditResults));
    }
  }
}
