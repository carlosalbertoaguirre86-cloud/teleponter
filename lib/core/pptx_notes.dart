// Extrae las notas del presentador de un archivo .pptx (ZIP + XML),
// sin dependencias externas. Port de PresentationNotesExtractor.swift.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

class PptxException implements Exception {
  PptxException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Lector ZIP mínimo (directorio central + deflate/stored).
class _ZipReader {
  _ZipReader(this.bytes) : data = ByteData.sublistView(bytes);
  final Uint8List bytes;
  final ByteData data;

  Map<String, Uint8List Function()> entries() {
    // Buscar el "End of central directory" (firma 0x06054b50).
    var eocd = -1;
    final minPos = (bytes.length - 22 - 65535).clamp(0, bytes.length);
    for (var i = bytes.length - 22; i >= minPos; i--) {
      if (data.getUint32(i, Endian.little) == 0x06054b50) {
        eocd = i;
        break;
      }
    }
    if (eocd < 0) throw PptxException('El archivo no es un .pptx válido.');
    final count = data.getUint16(eocd + 10, Endian.little);
    var p = data.getUint32(eocd + 16, Endian.little);
    final result = <String, Uint8List Function()>{};
    for (var n = 0; n < count; n++) {
      if (data.getUint32(p, Endian.little) != 0x02014b50) break;
      final method = data.getUint16(p + 10, Endian.little);
      final compSize = data.getUint32(p + 20, Endian.little);
      final nameLen = data.getUint16(p + 28, Endian.little);
      final extraLen = data.getUint16(p + 30, Endian.little);
      final commentLen = data.getUint16(p + 32, Endian.little);
      final localOffset = data.getUint32(p + 42, Endian.little);
      final name = utf8.decode(bytes.sublist(p + 46, p + 46 + nameLen),
          allowMalformed: true);
      result[name] = () {
        final lNameLen = data.getUint16(localOffset + 26, Endian.little);
        final lExtraLen = data.getUint16(localOffset + 28, Endian.little);
        final start = localOffset + 30 + lNameLen + lExtraLen;
        final raw = Uint8List.sublistView(bytes, start, start + compSize);
        if (method == 0) return raw;
        if (method == 8) {
          return Uint8List.fromList(ZLibDecoder(raw: true).convert(raw));
        }
        throw PptxException('Compresión ZIP no soportada ($method).');
      };
      p += 46 + nameLen + extraLen + commentLen;
    }
    return result;
  }
}

String _decodeEntities(String s) => s
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&quot;', '"')
    .replaceAll('&apos;', "'")
    .replaceAllMapped(RegExp(r'&#x([0-9a-fA-F]+);'),
        (m) => String.fromCharCode(int.parse(m[1]!, radix: 16)))
    .replaceAllMapped(
        RegExp(r'&#(\d+);'), (m) => String.fromCharCode(int.parse(m[1]!)))
    .replaceAll('&amp;', '&');

/// Convierte el XML de una diapositiva de notas en texto.
String parseNotesXml(String xml) {
  const skipTypes = {'sldNum', 'sldImg', 'dt', 'hdr', 'ftr'};
  final tag =
      RegExp(r'<(/?)([A-Za-z0-9_]+:)?([A-Za-z0-9_]+)([^>]*?)(/?)>|([^<]+)');
  final paragraphs = <String>[];
  var insideBody = false, insideParagraph = false, insideRun = false;
  var skip = false;
  var paragraph = StringBuffer();

  for (final m in tag.allMatches(xml)) {
    final text = m[6];
    if (text != null) {
      if (insideRun) paragraph.write(_decodeEntities(text));
      continue;
    }
    final closing = m[1] == '/';
    final name = m[3]!;
    final attrs = m[4] ?? '';
    final selfClosing = m[5] == '/';

    if (!closing) {
      if (name == 'sp') skip = false;
      if (name == 'ph') {
        final t = RegExp(r'type="([^"]*)"').firstMatch(attrs)?[1] ?? '';
        if (skipTypes.contains(t)) skip = true;
      }
      if (name == 'txBody') insideBody = true;
      if (name == 'p' && insideBody && !skip && !selfClosing) {
        insideParagraph = true;
        paragraph = StringBuffer();
      }
      if (name == 'p' && insideBody && !skip && selfClosing) {
        paragraphs.add('');
      }
      if (name == 't' && insideParagraph && !selfClosing) insideRun = true;
      if (name == 'br' && insideParagraph) paragraph.write('\n');
    }
    if (closing || selfClosing) {
      if (name == 't') insideRun = false;
      if (name == 'p' && insideParagraph && closing) {
        insideParagraph = false;
        paragraphs.add(paragraph.toString());
      }
      if (name == 'txBody' && closing) insideBody = false;
      if (name == 'sp' && closing) skip = false;
    }
  }
  return paragraphs.join('\n');
}

/// Devuelve una página por diapositiva con notas.
List<String> extractPptxNotes(Uint8List pptxBytes) {
  final entries = _ZipReader(pptxBytes).entries();
  final re = RegExp(r'^ppt/notesSlides/notesSlide(\d+)\.xml$');
  final files = entries.keys.where(re.hasMatch).toList()
    ..sort((a, b) => int.parse(re.firstMatch(a)![1]!)
        .compareTo(int.parse(re.firstMatch(b)![1]!)));
  if (files.isEmpty) {
    throw PptxException('Esta presentación no tiene notas del presentador.');
  }
  final pages = <String>[];
  for (final f in files) {
    final xml = utf8.decode(entries[f]!(), allowMalformed: true);
    final text = parseNotesXml(xml).trim();
    if (text.isEmpty || int.tryParse(text) != null) continue;
    pages.add(text);
  }
  if (pages.isEmpty) {
    throw PptxException('Esta presentación no tiene notas del presentador.');
  }
  return pages;
}
