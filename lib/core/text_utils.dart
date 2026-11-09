// Utilidades de texto compartidas por el teleprompter.
// Port de Textream (MIT, (c) 2026 Fatih Kadir Akin) a Dart.

final RegExp _letterOrNumber = RegExp(r'[\p{L}\p{N}]', unicode: true);
final RegExp _whitespace = RegExp(r'\s', unicode: true);
final RegExp _cjk = RegExp(
  r'[ᄀ-ᇿ⺀-⿿぀-ヿ㄀-ㇿ㐀-䶿'
  r'一-鿿가-힯豈-﫿]',
);

bool isLetterOrNumber(String ch) => _letterOrNumber.hasMatch(ch);
bool isWhitespaceChar(String ch) => _whitespace.hasMatch(ch);

/// Divide el texto en palabras. Los caracteres CJK se separan uno a uno
/// (no usan espacios), igual que en Textream.
List<String> splitTextIntoWords(String text) {
  final tokens =
      text.replaceAll('\n', ' ').split(_whitespace).where((t) => t.isNotEmpty);
  final result = <String>[];
  for (final token in tokens) {
    if (!_cjk.hasMatch(token)) {
      result.add(token);
      continue;
    }
    final buffer = StringBuffer();
    for (final rune in token.runes) {
      final ch = String.fromCharCode(rune);
      if (_cjk.hasMatch(ch)) {
        if (buffer.isNotEmpty) {
          result.add(buffer.toString());
          buffer.clear();
        }
        result.add(ch);
      } else {
        buffer.write(ch);
      }
    }
    if (buffer.isNotEmpty) result.add(buffer.toString());
  }
  return result;
}

/// Minúsculas y sólo letras, números y espacios.
String normalizeSpoken(String text) {
  final lower = text.toLowerCase();
  final sb = StringBuffer();
  for (final rune in lower.runes) {
    final ch = String.fromCharCode(rune);
    if (isLetterOrNumber(ch) || isWhitespaceChar(ch)) sb.write(ch);
  }
  return sb.toString();
}

String lettersAndNumbersOnly(String word) {
  final sb = StringBuffer();
  for (final rune in word.runes) {
    final ch = String.fromCharCode(rune);
    if (isLetterOrNumber(ch)) sb.write(ch);
  }
  return sb.toString();
}

/// Palabra que no se lee en voz alta: anotaciones [entre corchetes] o
/// tokens sin letras ni números (emoji, guiones...).
bool isAnnotationWord(String word) {
  if (word.startsWith('[') && word.endsWith(']')) return true;
  return lettersAndNumbersOnly(word).isEmpty;
}

/// Para cada palabra indica si forma parte de una anotación [ ... ].
List<bool> annotationFlags(List<String> words) {
  final closingAtOrAfter = List<bool>.filled(words.length, false);
  var hasClosing = false;
  for (var i = words.length - 1; i >= 0; i--) {
    if (words[i].contains(']')) hasClosing = true;
    closingAtOrAfter[i] = hasClosing;
  }
  final flags = <bool>[];
  var inside = false;
  for (var i = 0; i < words.length; i++) {
    final word = words[i];
    final begins = word.startsWith('[') && closingAtOrAfter[i];
    flags.add(inside || begins || isAnnotationWord(word));
    if (begins) inside = true;
    if (inside && word.contains(']')) inside = false;
  }
  return flags;
}

/// Rango [start, end) de caracteres.
class CharRange {
  const CharRange(this.start, this.end);
  final int start;
  final int end;
  bool contains(int i) => i >= start && i < end;
  @override
  String toString() => '[$start,$end)';
}

List<CharRange> annotationRanges(String text) {
  final ranges = <CharRange>[];
  int? opening;
  for (var i = 0; i < text.length; i++) {
    final c = text[i];
    if (c == '[' && opening == null) {
      opening = i;
    } else if (c == ']' && opening != null) {
      ranges.add(CharRange(opening, i + 1));
      opening = null;
    }
  }
  return ranges;
}

int advancePastAnnotations(String text, List<CharRange> ranges, int offset) {
  var current = offset.clamp(0, text.length);
  var skipped = false;
  while (current < text.length) {
    final inRange = ranges.where((r) => r.contains(current));
    if (inRange.isNotEmpty) {
      current = inRange.first.end;
      skipped = true;
      continue;
    }
    var next = current;
    while (next < text.length && isWhitespaceChar(text[next])) {
      next++;
    }
    final starting = ranges.where((r) => r.start == next);
    if (starting.isNotEmpty) {
      current = starting.first.end;
      skipped = true;
      continue;
    }
    return skipped ? next : current;
  }
  return current;
}

/// Desplazamientos de inicio de cada palabra dentro del texto colapsado
/// (palabras unidas con un espacio).
List<int> wordStartOffsets(List<String> words) {
  final offsets = <int>[];
  var pos = 0;
  for (final w in words) {
    offsets.add(pos);
    pos += w.length + 1;
  }
  return offsets;
}
