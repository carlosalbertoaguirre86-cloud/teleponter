// Nivel del micrófono para el modo "activado por voz".

import 'dart:async';
import 'dart:typed_data';

import 'package:record/record.dart';

import '../core/voice_activity.dart';

class MicLevelService {
  AudioRecorder? _recorder;
  StreamSubscription<Uint8List>? _sub;

  void Function(double level)? onLevel;
  void Function(String message)? onError;

  bool get isRunning => _sub != null;

  Future<void> start() async {
    if (_sub != null) return;
    final recorder = AudioRecorder();
    _recorder = recorder;
    try {
      if (!await recorder.hasPermission()) {
        onError?.call('Permiso de micrófono denegado.');
        return;
      }
      final stream = await recorder.startStream(const RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: 16000,
        numChannels: 1,
      ));
      _sub = stream.listen((chunk) {
        onLevel?.call(rmsLevelPcm16(chunk));
      });
    } catch (e) {
      onError?.call('No se pudo abrir el micrófono: $e');
    }
  }

  Future<void> stop() async {
    await _sub?.cancel();
    _sub = null;
    try {
      await _recorder?.stop();
      await _recorder?.dispose();
    } catch (_) {}
    _recorder = null;
  }
}
