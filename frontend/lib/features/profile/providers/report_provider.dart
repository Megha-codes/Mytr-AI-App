import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/api/api_client.dart';

class ReportState {
  final bool isGenerating;
  final String? currentJobId;
  final String? downloadUrl;
  final String? error;

  ReportState({this.isGenerating = false, this.currentJobId, this.downloadUrl, this.error});

  ReportState copyWith({bool? isGenerating, String? currentJobId, String? downloadUrl, String? error}) {
    return ReportState(
      isGenerating: isGenerating ?? this.isGenerating,
      currentJobId: currentJobId ?? this.currentJobId,
      downloadUrl: downloadUrl ?? this.downloadUrl,
      error: error ?? this.error,
    );
  }
}

class ReportNotifier extends AutoDisposeNotifier<ReportState> {
  Timer? _pollingTimer;

  @override
  ReportState build() {
    ref.onDispose(() => _pollingTimer?.cancel());
    return ReportState();
  }

  Future<void> generate() async {
    state = state.copyWith(isGenerating: true, error: null);
    
    try {
      final response = await ref.read(apiClientProvider).post('/reports/generate');
      final jobId = response.data['job_id'];
      state = state.copyWith(currentJobId: jobId);
      _startPolling(jobId);
    } catch (e) {
      state = state.copyWith(isGenerating: false, error: e.toString());
    }
  }

  void _startPolling(String jobId) {
    _pollingTimer?.cancel();
    _pollingTimer = Timer.periodic(const Duration(seconds: 2), (timer) async {
      try {
        final response = await ref.read(apiClientProvider).get('/reports/$jobId/status');
        final status = response.data['status'];
        
        if (status == 'COMPLETED') {
          timer.cancel();
          state = state.copyWith(
            isGenerating: false,
            downloadUrl: response.data['download_url'],
          );
        } else if (status == 'FAILED') {
          timer.cancel();
          state = state.copyWith(isGenerating: false, error: 'Report generation failed');
        }
      } catch (e) {
        timer.cancel();
        state = state.copyWith(isGenerating: false, error: e.toString());
      }
    });
  }
}

final reportProvider = NotifierProvider.autoDispose<ReportNotifier, ReportState>(() {
  return ReportNotifier();
});
