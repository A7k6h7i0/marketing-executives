import 'telecaller_api.dart';
import 'telecaller_oem_recording.dart';
import 'telecaller_recording_setup.dart';

enum RecordingProcessPhase {
  idle,
  scanning,
  uploading,
  success,
  failed,
}

class RecordingProcessState {
  const RecordingProcessState({
    required this.phase,
    this.detail,
    this.fileName,
    this.error,
  });

  final RecordingProcessPhase phase;
  final String? detail;
  final String? fileName;
  final String? error;
}

typedef ProcessListener = void Function(RecordingProcessState state);

/// Scan linked OEM folder and upload the newest call recording.
class TelecallerRecordingUploader {
  TelecallerRecordingUploader(this._api);

  final TelecallerApi _api;

  Future<bool> runAutoUpload({
    required String callId,
    DateTime? callStartedAt,
    required ProcessListener onState,
  }) async {
    await TelecallerRecordingSetup.load();
    if (!TelecallerRecordingSetup.hasLinkedFolder) {
      onState(const RecordingProcessState(
        phase: RecordingProcessPhase.failed,
        error: 'No recordings folder linked',
        detail: 'Finish telecaller setup and choose your call recordings folder.',
      ));
      return false;
    }

    final label = TelecallerRecordingSetup.folderLabel;
    onState(RecordingProcessState(
      phase: RecordingProcessPhase.scanning,
      detail: label != null
          ? 'Scanning $label…'
          : 'Scanning for call recording…',
    ));

    await Future.delayed(const Duration(seconds: 2));

    final modifiedAfter = callStartedAt != null
        ? callStartedAt.subtract(const Duration(seconds: 90))
        : DateTime.now().subtract(const Duration(minutes: 5));

    final hit = await TelecallerOemRecording.findNewestWithRetry(
      modifiedAfter: modifiedAfter,
      attempts: 12,
      delay: const Duration(seconds: 2),
    );

    if (hit == null) {
      onState(const RecordingProcessState(
        phase: RecordingProcessPhase.failed,
        error: 'No new recording found',
        detail: 'Auto-scan did not find a call recording file. You can skip and log the outcome.',
      ));
      return false;
    }

    onState(RecordingProcessState(
      phase: RecordingProcessPhase.uploading,
      fileName: hit.displayName,
      detail: 'Uploading ${hit.displayName}…',
    ));

    try {
      await _api.attachCallRecordingFile(
        callId: callId,
        filePath: hit.path,
        fileName: hit.displayName,
      );
      await TelecallerRecordingSetup.markLastUploaded(hit.path, hit.modifiedMs);
      onState(const RecordingProcessState(
        phase: RecordingProcessPhase.success,
        detail: 'Recording uploaded',
      ));
      return true;
    } catch (e) {
      onState(RecordingProcessState(
        phase: RecordingProcessPhase.failed,
        error: formatTelecallerError(e),
        detail: 'Upload failed',
        fileName: hit.displayName,
      ));
      return false;
    }
  }

  Future<bool> uploadManualPick({
    required String callId,
    required String filePath,
    required String fileName,
    required ProcessListener onState,
  }) async {
    onState(RecordingProcessState(
      phase: RecordingProcessPhase.uploading,
      fileName: fileName,
      detail: 'Uploading $fileName…',
    ));
    try {
      await _api.attachCallRecordingFile(
        callId: callId,
        filePath: filePath,
        fileName: fileName,
      );
      onState(const RecordingProcessState(
        phase: RecordingProcessPhase.success,
        detail: 'Recording uploaded',
      ));
      return true;
    } catch (e) {
      onState(RecordingProcessState(
        phase: RecordingProcessPhase.failed,
        error: formatTelecallerError(e),
        fileName: fileName,
      ));
      return false;
    }
  }
}
