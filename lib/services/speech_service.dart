// Reconocimiento de voz continuo sobre speech_to_text.
// Android detiene el reconocedor tras cada pausa, así que se reinicia solo
// mientras el teleprompter esté escuchando.

import 'dart:async';

import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

class SpeechService {
  final SpeechToText _stt = SpeechToText();
  bool _initialized = false;
  bool _wantListening = false;
  bool _restartScheduled = false;
  int _session = 0;
  String localeId = '';

  /// Texto acumulado de la sesión actual del reconocedor.
  void Function(String text, int session)? onTranscript;

  /// Nivel de audio normalizado 0..1.
  void Function(double level)? onLevel;

  /// Se llama cuando empieza una nueva sesión (transcripción desde cero).
  void Function(int session)? onNewSession;

  void Function(String message)? onError;

  bool get isListening => _wantListening;

  Future<bool> ensureInitialized() async {
    if (_initialized) return true;
    try {
      _initialized = await _stt.initialize(
        onError: _handleError,
        onStatus: _handleStatus,
      );
    } catch (e) {
      onError?.call('No se pudo iniciar el reconocimiento de voz: $e');
      _initialized = false;
    }
    if (!_initialized) {
      onError?.call(
          'Reconocimiento de voz no disponible. Revisa el permiso de micrófono '
          'y que el dispositivo tenga un servicio de voz instalado.');
    }
    return _initialized;
  }

  Future<List<LocaleName>> locales() async {
    if (!await ensureInitialized()) return const [];
    return _stt.locales();
  }

  Future<void> start() async {
    if (!await ensureInitialized()) return;
    _wantListening = true;
    await _listen();
  }

  Future<void> stop() async {
    _wantListening = false;
    try {
      await _stt.stop();
    } catch (_) {}
  }

  Future<void> _listen() async {
    if (!_wantListening) return;
    _session++;
    onNewSession?.call(_session);
    final session = _session;
    try {
      // ignore: deprecated_member_use
      await _stt.listen(
        onResult: (SpeechRecognitionResult r) {
          if (session != _session) return;
          onTranscript?.call(r.recognizedWords, session);
        },
        onSoundLevelChange: (db) {
          // Android entrega ~ -2..10 dB; otros valores se acotan.
          final level = ((db + 2) / 12).clamp(0.0, 1.0);
          onLevel?.call(level);
        },
        // ignore: deprecated_member_use
        localeId: localeId.isEmpty ? null : localeId,
        // ignore: deprecated_member_use
        listenFor: const Duration(minutes: 10),
        // ignore: deprecated_member_use
        pauseFor: const Duration(seconds: 30),
        listenOptions: SpeechListenOptions(
          partialResults: true,
          cancelOnError: false,
          listenMode: ListenMode.dictation,
        ),
      );
    } catch (e) {
      _scheduleRestart(const Duration(milliseconds: 600));
    }
  }

  void _handleStatus(String status) {
    if ((status == SpeechToText.doneStatus ||
            status == SpeechToText.notListeningStatus) &&
        _wantListening) {
      _scheduleRestart(const Duration(milliseconds: 120));
    }
  }

  void _handleError(SpeechRecognitionError error) {
    final msg = error.errorMsg;
    if (msg == 'error_permission' || msg == 'error_insufficient_permissions') {
      _wantListening = false;
      onError?.call('Permiso de micrófono denegado.');
      return;
    }
    // error_no_match / error_speech_timeout son normales en silencios.
    if (_wantListening) _scheduleRestart(const Duration(milliseconds: 300));
  }

  void _scheduleRestart(Duration delay) {
    if (_restartScheduled) return;
    _restartScheduled = true;
    Timer(delay, () async {
      _restartScheduled = false;
      if (!_wantListening) return;
      if (_stt.isListening) return;
      await _listen();
    });
  }
}
