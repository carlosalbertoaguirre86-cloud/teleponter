// Alineación entre lo que dice el reconocedor de voz y el guion.
// Port fiel del algoritmo de Textream (SpeechRecognizer.swift +
// SpeechTextAlignment.swift). MIT, (c) 2026 Fatih Kadir Akin.

import 'dart:math' as math;

import 'text_utils.dart';

int bestOffset(int characterResult, int wordResult, {int tolerance = 20}) {
  if ((characterResult - wordResult).abs() <= tolerance) {
    return (characterResult + wordResult) ~/ 2;
  }
  return math.max(characterResult, wordResult);
}

bool shouldCommit({
  required int characterResult,
  required int wordResult,
  required int current,
  required int rawCandidate,
  required int candidate,
  required bool confirmed,
}) {
  final bothProgressed = math.min(characterResult, wordResult) > 0;
  final skippedAnnotation = candidate > rawCandidate;
  final smallStep = candidate - current <= 15;
  return bothProgressed || skippedAnnotation || confirmed || smallStep;
}

int editDistance(String a, String b) {
  if (a.isEmpty) return b.length;
  if (b.isEmpty) return a.length;
  final dp = List<int>.generate(b.length + 1, (i) => i);
  for (var i = 1; i <= a.length; i++) {
    var prev = dp[0];
    dp[0] = i;
    for (var j = 1; j <= b.length; j++) {
      final temp = dp[j];
      dp[j] = a[i - 1] == b[j - 1]
          ? prev
          : math.min(prev, math.min(dp[j], dp[j - 1])) + 1;
      prev = temp;
    }
  }
  return dp[b.length];
}

int _sharedPrefix(String a, String b) {
  final n = math.min(a.length, b.length);
  var i = 0;
  while (i < n && a[i] == b[i]) {
    i++;
  }
  return i;
}

bool isFuzzyMatch(String a, String b) {
  if (a.isEmpty || b.isEmpty) return false;
  if (a == b) return true;
  final shorter = math.min(a.length, b.length);
  if (shorter >= 3 && (a.startsWith(b) || b.startsWith(a))) return true;
  final shared = _sharedPrefix(a, b);
  if (shorter >= 3 && shared >= math.max(3, shorter * 3 ~/ 5)) return true;
  if (shorter <= 2) return false;
  final dist = editDistance(a, b);
  if (shorter <= 4) return dist <= 1;
  if (shorter <= 8) return dist <= 2;
  return dist <= math.max(a.length, b.length) ~/ 3;
}

/// Sigue la posición de lectura dentro de un texto a partir de las
/// transcripciones parciales del reconocedor de voz.
class SpeechTracker {
  String _source = '';
  List<CharRange> _ranges = const [];
  int recognizedCharCount = 0;
  int _matchStartOffset = 0;
  final List<int> _recent = [];
  String _anchorPrefix = '';
  DateTime _lastJumpAt = DateTime.fromMillisecondsSinceEpoch(0);
  String lastSpokenText = '';

  String get sourceText => _source;

  void reset(String text) {
    _source = splitTextIntoWords(text).join(' ');
    _ranges = annotationRanges(_source);
    recognizedCharCount = _advance(0);
    _matchStartOffset = recognizedCharCount;
    _recent.clear();
    _anchorPrefix = '';
    lastSpokenText = '';
  }

  /// Actualiza el texto conservando el progreso (modo director).
  void updateText(String text, int preservingCharCount) {
    _source = splitTextIntoWords(text).join(' ');
    _ranges = annotationRanges(_source);
    recognizedCharCount =
        _advance(math.min(preservingCharCount, _source.length));
    _matchStartOffset = recognizedCharCount;
    _recent.clear();
  }

  /// Llamar cuando el reconocedor empieza una sesión nueva (transcripción
  /// desde cero): lo ya leído se convierte en el nuevo punto de partida.
  void beginNewTranscript() {
    _matchStartOffset = recognizedCharCount;
    _anchorPrefix = '';
    _recent.clear();
    lastSpokenText = '';
  }

  void jumpTo(int charOffset) {
    final target = _advance(charOffset.clamp(0, _source.length));
    recognizedCharCount = target;
    _matchStartOffset = target;
    _recent.clear();
    _anchorPrefix = lastSpokenText;
    _lastJumpAt = DateTime.now();
  }

  int _advance(int offset) => advancePastAnnotations(_source, _ranges, offset);

  /// Procesa una transcripción (acumulada) y devuelve true si avanzó.
  bool process(String fullSpoken, {DateTime? now}) {
    lastSpokenText = fullSpoken;
    final t = now ?? DateTime.now();
    if (t.difference(_lastJumpAt).inMilliseconds <= 300) return false;

    var spoken = fullSpoken;
    if (_anchorPrefix.isNotEmpty) {
      final common = _sharedPrefix(_anchorPrefix, fullSpoken);
      final trimLen = math.min(
          fullSpoken.length, math.max(common, _anchorPrefix.length - 24));
      spoken = fullSpoken.substring(trimLen);
    }
    if (spoken.isEmpty) return false;

    final charResult = _charLevelMatch(spoken);
    final wordResult = _wordLevelMatch(spoken);
    final best = bestOffset(charResult, wordResult);
    final rawCandidate = math.min(_matchStartOffset + best, _source.length);
    final candidate = _advance(rawCandidate);
    if (candidate <= recognizedCharCount) return false;

    _recent.add(candidate);
    if (_recent.length > 3) _recent.removeAt(0);
    var confirmed = false;
    if (_recent.length >= 2) {
      final agree = _recent.where((p) => (p - candidate).abs() <= 10).length;
      confirmed = agree >= 2;
    }
    if (shouldCommit(
      characterResult: charResult,
      wordResult: wordResult,
      current: recognizedCharCount,
      rawCandidate: rawCandidate,
      candidate: candidate,
      confirmed: confirmed,
    )) {
      recognizedCharCount = candidate;
      return true;
    }
    return false;
  }

  int _charLevelMatch(String spokenText) {
    final src = _source.substring(_matchStartOffset).toLowerCase();
    final spk = normalizeSpoken(spokenText);
    var si = 0, ri = 0, lastGood = 0;

    bool alnum(String c) => isLetterOrNumber(c);

    while (si < src.length && ri < spk.length) {
      final sc = src[si];
      final rc = spk[ri];
      if (sc == '[') {
        final close = src.indexOf(']', si);
        if (close >= 0) {
          si = close + 1;
          lastGood = si;
          continue;
        }
      }
      if (!alnum(sc)) {
        si++;
        continue;
      }
      if (!alnum(rc)) {
        ri++;
        continue;
      }
      if (sc == rc) {
        si++;
        ri++;
        lastGood = si;
        continue;
      }
      var found = false;
      final maxSkipR = math.min(5, spk.length - ri - 1);
      for (var k = 1; k <= maxSkipR; k++) {
        if (spk[ri + k] == sc) {
          ri += k;
          found = true;
          break;
        }
      }
      if (found) continue;
      final maxSkipS = math.min(5, src.length - si - 1);
      for (var k = 1; k <= maxSkipS; k++) {
        if (src[si + k] == rc) {
          si += k;
          found = true;
          break;
        }
      }
      if (found) continue;
      ri++;
    }

    while (si < src.length) {
      if (src[si] == '[' && src.indexOf(']', si) >= 0) {
        si = src.indexOf(']', si) + 1;
        lastGood = si;
      } else if (!alnum(src[si])) {
        si++;
        lastGood = si;
      } else {
        break;
      }
    }
    return lastGood;
  }

  int _wordLevelMatch(String spokenText) {
    final remaining = _source.substring(_matchStartOffset);
    final sourceWords =
        remaining.split(' ').where((w) => w.isNotEmpty).toList();
    final spokenWords = splitTextIntoWords(spokenText.toLowerCase());

    var si = 0, ri = 0, matched = 0;
    var inside = false;

    bool beginsAnnotation(int i) =>
        sourceWords[i].startsWith('[') &&
        sourceWords.skip(i).any((w) => w.contains(']'));

    void skipSourceWord() {
      matched += sourceWords[si].length;
      if (si < sourceWords.length - 1) matched += 1;
      si++;
    }

    while (si < sourceWords.length && ri < spokenWords.length) {
      final begins = beginsAnnotation(si);
      if (inside || begins || isAnnotationWord(sourceWords[si])) {
        if (begins) inside = true;
        if (sourceWords[si].contains(']')) inside = false;
        skipSourceWord();
        continue;
      }
      final srcWord = lettersAndNumbersOnly(sourceWords[si].toLowerCase());
      final spkWord = lettersAndNumbersOnly(spokenWords[ri]);

      if (srcWord == spkWord || isFuzzyMatch(srcWord, spkWord)) {
        matched += sourceWords[si].length;
        si++;
        ri++;
        if (si < sourceWords.length) matched += 1;
        continue;
      }
      var found = false;
      final maxSpk = math.min(5, spokenWords.length - ri - 1);
      for (var k = 1; k <= maxSpk; k++) {
        final next = lettersAndNumbersOnly(spokenWords[ri + k]);
        if (srcWord == next || isFuzzyMatch(srcWord, next)) {
          ri += k;
          found = true;
          break;
        }
      }
      if (found) continue;
      final maxSrc = math.min(5, sourceWords.length - si - 1);
      for (var k = 1; k <= maxSrc; k++) {
        final next = lettersAndNumbersOnly(sourceWords[si + k].toLowerCase());
        if (next == spkWord || isFuzzyMatch(next, spkWord)) {
          for (var s = 0; s < k; s++) {
            matched += sourceWords[si + s].length + 1;
          }
          si += k;
          found = true;
          break;
        }
      }
      if (found) continue;
      if (srcWord.isEmpty) {
        skipSourceWord();
        continue;
      }
      ri++;
    }

    while (si < sourceWords.length) {
      final begins = beginsAnnotation(si);
      if (!(inside || begins || isAnnotationWord(sourceWords[si]))) break;
      if (begins) inside = true;
      if (sourceWords[si].contains(']')) inside = false;
      skipSourceWord();
    }
    return matched;
  }
}
