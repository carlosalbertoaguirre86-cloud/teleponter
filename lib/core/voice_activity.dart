// Detector de actividad de voz (port de VoiceActivityDetector.swift).

import 'dart:math' as math;
import 'dart:typed_data';

class VoiceActivityDetector {
  VoiceActivityDetector({
    this.activationLevel = 0.012,
    this.immediateActivationLevel = 0.04,
    this.requiredActiveFrames = 2,
    this.hangover = const Duration(milliseconds: 750),
  });

  final double activationLevel;
  final double immediateActivationLevel;
  final int requiredActiveFrames;
  final Duration hangover;

  int _consecutive = 0;
  int _activeUntilMs = -1;

  void process(double level, int timestampMs) {
    if (level >= immediateActivationLevel) {
      _consecutive = requiredActiveFrames;
      _extend(timestampMs);
    } else if (level >= activationLevel) {
      _consecutive++;
      if (_consecutive >= requiredActiveFrames) _extend(timestampMs);
    } else {
      _consecutive = 0;
    }
  }

  bool isActive(int timestampMs) => timestampMs < _activeUntilMs;

  void reset() {
    _consecutive = 0;
    _activeUntilMs = -1;
  }

  void _extend(int t) {
    _activeUntilMs = math.max(_activeUntilMs, t + hangover.inMilliseconds);
  }
}

/// Nivel RMS (0..1) de un bloque PCM de 16 bits little-endian.
double rmsLevelPcm16(Uint8List bytes) {
  final n = bytes.lengthInBytes ~/ 2;
  if (n == 0) return 0;
  final data = ByteData.sublistView(bytes);
  var sum = 0.0;
  for (var i = 0; i < n; i++) {
    final s = data.getInt16(i * 2, Endian.little) / 32768.0;
    sum += s * s;
  }
  return math.sqrt(sum / n);
}
