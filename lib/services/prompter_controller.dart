// Estado central del teleprompter: guion, posición, modo de guía,
// micrófono y avance de páginas.

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../core/settings.dart';
import '../core/speech_alignment.dart';
import '../core/text_utils.dart';
import '../core/voice_activity.dart';
import 'mic_level_service.dart';
import 'speech_service.dart';

class PrompterController extends ChangeNotifier {
  PrompterController(this.settings) {
    _speech.onTranscript = _onTranscript;
    _speech.onNewSession = (_) => _tracker.beginNewTranscript();
    _speech.onLevel = _onLevel;
    _speech.onError = _setError;
    _mic.onLevel = _onLevel;
    _mic.onError = _setError;
  }

  final AppSettings settings;
  final SpeechService _speech = SpeechService();
  final MicLevelService _mic = MicLevelService();
  final SpeechTracker _tracker = SpeechTracker();
  final VoiceActivityDetector _vad = VoiceActivityDetector();
  final Stopwatch _clock = Stopwatch()..start();

  // Guion
  List<String> pages = [''];
  int pageIndex = 0;

  // Página activa
  List<String> words = const [];
  List<int> wordOffsets = const [];
  List<bool> annotation = const [];
  String collapsed = '';

  /// Posición en palabras (fraccional en los modos de desplazamiento).
  double wordPosition = 0;

  /// Caracteres leídos dentro de [collapsed].
  int get highlightedCharCount => switch (mode) {
        GuidanceMode.wordTracking => _tracker.recognizedCharCount,
        _ => _charsForWordPosition(wordPosition),
      };

  bool active = false; // teleprompter visible
  bool paused = false;
  bool muted = false;
  bool done = false;
  bool userScrolling = false;
  int? countdown; // segundos hasta la página siguiente
  String? error;
  String lastSpokenText = '';
  final List<double> levels = List<double>.filled(24, 0);

  late GuidanceMode mode = settings.guidance;
  Timer? _ticker;
  Timer? _countdownTimer;
  int _lastTickMs = 0;

  /// Lo pone la UI para cerrar el teleprompter al terminar.
  VoidCallback? onFinished;

  bool get hasNextPage => _nextNonEmptyPage(pageIndex) != null;
  bool get isSpeaking => _vad.isActive(_clock.elapsedMilliseconds);
  bool get usesMicrophone => mode != GuidanceMode.classic;
  bool get isListening => usesMicrophone && active && !muted && !paused;
  double get progress => collapsed.isEmpty
      ? 0
      : (highlightedCharCount / collapsed.length).clamp(0.0, 1.0);

  int? _nextNonEmptyPage(int from) {
    for (var i = from + 1; i < pages.length; i++) {
      if (pages[i].trim().isNotEmpty) return i;
    }
    return null;
  }

  // ---------------------------------------------------------------------
  // Ciclo de vida

  Future<void> start({int? fromPage}) async {
    mode = settings.guidance;
    _speech.localeId = settings.speechLocale;
    var idx = fromPage ?? pageIndex;
    if (idx >= pages.length || pages[idx].trim().isEmpty) {
      idx = _nextNonEmptyPage(-1) ?? 0;
    }
    error = null;
    active = true;
    paused = false;
    done = false;
    _loadPage(idx);
    await _startAudio();
    _startTicker();
    notifyListeners();
  }

  Future<void> stop() async {
    active = false;
    paused = false;
    countdown = null;
    _countdownTimer?.cancel();
    _ticker?.cancel();
    _ticker = null;
    await _stopAudio();
    notifyListeners();
  }

  void _loadPage(int idx) {
    pageIndex = idx;
    final text = pages[idx];
    words = splitTextIntoWords(text);
    collapsed = words.join(' ');
    wordOffsets = wordStartOffsets(words);
    annotation = annotationFlags(words);
    _tracker.reset(text);
    wordPosition = 0;
    _skipAnnotationsForward();
    done = false;
    countdown = null;
  }

  Future<void> _startAudio() async {
    if (muted || paused) return;
    switch (mode) {
      case GuidanceMode.wordTracking:
        await _speech.start();
      case GuidanceMode.voiceActivated:
        await _mic.start();
      case GuidanceMode.classic:
        break;
    }
  }

  Future<void> _stopAudio() async {
    await _speech.stop();
    await _mic.stop();
    _vad.reset();
    levels.fillRange(0, levels.length, 0);
  }

  void _startTicker() {
    _ticker?.cancel();
    _lastTickMs = _clock.elapsedMilliseconds;
    _ticker = Timer.periodic(const Duration(milliseconds: 33), (_) => _tick());
  }

  void _tick() {
    final now = _clock.elapsedMilliseconds;
    final dt = (now - _lastTickMs) / 1000.0;
    _lastTickMs = now;
    if (!active || done || countdown != null) return;
    var changed = false;
    if (!paused && !userScrolling) {
      if (mode == GuidanceMode.classic ||
          (mode == GuidanceMode.voiceActivated && !muted && isSpeaking)) {
        wordPosition = math.min(
            words.length.toDouble(), wordPosition + settings.speed * dt);
        _skipAnnotationsForward();
        changed = true;
      }
    }
    if (mode != GuidanceMode.classic) {
      // Decaimiento suave de la onda.
      for (var i = 0; i < levels.length; i++) {
        levels[i] *= 0.92;
      }
      changed = true;
    }
    if (changed) {
      _checkFinished();
      notifyListeners();
    }
  }

  void _skipAnnotationsForward() {
    var i = wordPosition.floor();
    while (i < words.length && annotation[i]) {
      i++;
    }
    if (i > wordPosition.floor()) wordPosition = i.toDouble();
  }

  int _charsForWordPosition(double pos) {
    final i = pos.floor();
    if (i <= 0) return 0;
    if (i >= words.length) return collapsed.length;
    return wordOffsets[i];
  }

  void _checkFinished() {
    if (done || collapsed.isEmpty) return;
    final finished = mode == GuidanceMode.wordTracking
        ? _tracker.recognizedCharCount >= collapsed.length
        : wordPosition >= words.length;
    if (!finished) return;
    done = true;
    final next = _nextNonEmptyPage(pageIndex);
    if (next != null && settings.autoAdvancePages) {
      countdown = 3;
      _countdownTimer?.cancel();
      _countdownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
        if (!active) return t.cancel();
        countdown = (countdown ?? 1) - 1;
        if (countdown! <= 0) {
          t.cancel();
          goToPage(next);
        } else {
          notifyListeners();
        }
      });
    } else if (next == null) {
      Timer(const Duration(milliseconds: 1200), () {
        if (active && done) onFinished?.call();
      });
    }
  }

  // ---------------------------------------------------------------------
  // Audio

  void _onTranscript(String text, int session) {
    if (!active || paused || muted || mode != GuidanceMode.wordTracking) {
      return;
    }
    lastSpokenText = text;
    if (_tracker.process(text)) {
      wordPosition = _wordIndexForChar(_tracker.recognizedCharCount).toDouble();
      _checkFinished();
    }
    notifyListeners();
  }

  void _onLevel(double level) {
    if (muted) level = 0;
    _vad.process(level, _clock.elapsedMilliseconds);
    levels.removeAt(0);
    // Escala visual: el RMS de voz rara vez supera 0.2.
    levels.add(
        mode == GuidanceMode.voiceActivated ? math.min(1.0, level * 6) : level);
  }

  void _setError(String message) {
    error = message;
    notifyListeners();
  }

  int _wordIndexForChar(int chars) {
    var lo = 0;
    for (var i = 0; i < wordOffsets.length; i++) {
      if (wordOffsets[i] <= chars) lo = i;
    }
    return chars >= collapsed.length ? words.length : lo;
  }

  // ---------------------------------------------------------------------
  // Acciones del usuario

  Future<void> togglePause() async {
    paused = !paused;
    if (paused) {
      await _stopAudio();
    } else {
      await _startAudio();
      _lastTickMs = _clock.elapsedMilliseconds;
    }
    notifyListeners();
  }

  Future<void> toggleMute() async {
    muted = !muted;
    if (muted) {
      await _stopAudio();
    } else if (!paused) {
      await _startAudio();
    }
    notifyListeners();
  }

  void jumpToWord(int index) {
    if (index < 0 || index >= words.length) return;
    countdown = null;
    _countdownTimer?.cancel();
    done = false;
    wordPosition = index.toDouble();
    _tracker.jumpTo(wordOffsets[index]);
    notifyListeners();
  }

  /// Desplazamiento manual (rueda del ratón / arrastre) en palabras.
  void nudge(double deltaWords) {
    wordPosition =
        (wordPosition + deltaWords).clamp(0, words.length.toDouble());
    _tracker.jumpTo(_charsForWordPosition(wordPosition));
    done = false;
    notifyListeners();
  }

  void setSpeed(double v) {
    settings.speed = v.clamp(0.5, 8.0);
    notifyListeners();
  }

  void goToPage(int idx) {
    if (idx < 0 || idx >= pages.length) return;
    _countdownTimer?.cancel();
    _loadPage(idx);
    _tracker.beginNewTranscript();
    notifyListeners();
  }

  void nextPage() {
    final n = _nextNonEmptyPage(pageIndex);
    if (n != null) goToPage(n);
  }

  void previousPage() {
    for (var i = pageIndex - 1; i >= 0; i--) {
      if (pages[i].trim().isNotEmpty) return goToPage(i);
    }
  }

  // ---------------------------------------------------------------------
  // Modo director

  /// Reemplaza el guion por un texto y arranca con seguimiento de palabras.
  Future<void> directorSetText(String text) async {
    pages = [text];
    pageIndex = 0;
    if (active) {
      _loadPage(0);
      notifyListeners();
    } else {
      await start(fromPage: 0);
    }
  }

  /// Edita el texto sin perder el progreso leído.
  void directorUpdateText(String text, int readCharCount) {
    pages = [text];
    pageIndex = 0;
    words = splitTextIntoWords(text);
    collapsed = words.join(' ');
    wordOffsets = wordStartOffsets(words);
    annotation = annotationFlags(words);
    _tracker.updateText(text, readCharCount);
    wordPosition = _wordIndexForChar(_tracker.recognizedCharCount).toDouble();
    done = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _countdownTimer?.cancel();
    _stopAudio();
    super.dispose();
  }
}
