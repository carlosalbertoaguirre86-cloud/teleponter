import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:teleponter/core/pptx_notes.dart';
import 'package:teleponter/core/speech_alignment.dart';
import 'package:teleponter/core/text_utils.dart';
import 'package:teleponter/core/voice_activity.dart';

DateTime _later(int i) => DateTime.now().add(Duration(seconds: 1 + i));

/// Simula transcripciones parciales crecientes palabra a palabra.
int feed(SpeechTracker t, String spoken) {
  final words = spoken.split(' ');
  for (var i = 1; i <= words.length; i++) {
    t.process(words.take(i).join(' '), now: _later(i));
  }
  return t.recognizedCharCount;
}

void main() {
  group('texto', () {
    test('divide palabras y CJK', () {
      expect(splitTextIntoWords('Hola  mundo\nadiós'),
          equals(['Hola', 'mundo', 'adiós']));
      expect(splitTextIntoWords('abc你好'), equals(['abc', '你', '好']));
    });

    test('anotaciones', () {
      final w = splitTextIntoWords('Hola [pausa larga] mundo');
      expect(annotationFlags(w), equals([false, true, true, false]));
      final text = w.join(' ');
      final r = annotationRanges(text);
      expect(r.length, equals(1));
      expect(advancePastAnnotations(text, r, 5), equals(19));
    });
  });

  group('coincidencia difusa', () {
    test('palabras parecidas', () {
      expect(isFuzzyMatch('teleprompter', 'teleprompters'), isTrue);
      expect(isFuzzyMatch('camino', 'camión'), isTrue);
      expect(isFuzzyMatch('de', 'en'), isFalse);
      expect(isFuzzyMatch('casa', 'perro'), isFalse);
      expect(editDistance('kitten', 'sitting'), equals(3));
    });
  });

  group('seguimiento de voz', () {
    const script = 'Bienvenidos a la demostración. [sonríe] Hoy vamos a hablar '
        'de teleprompters libres para Windows y Android.';

    test('avanza al leer en orden', () {
      final t = SpeechTracker()..reset(script);
      final pos = feed(t, 'bienvenidos a la demostración hoy vamos a hablar');
      final src = t.sourceText;
      expect(pos, greaterThan(src.indexOf('hablar')));
      expect(pos, lessThanOrEqualTo(src.indexOf('teleprompters')));
    });

    test('salta la anotación entre corchetes', () {
      final t = SpeechTracker()..reset(script);
      final pos = feed(t, 'bienvenidos a la demostración');
      expect(pos, greaterThan(t.sourceText.indexOf(']')));
    });

    test('tolera errores del reconocedor', () {
      final t = SpeechTracker()..reset(script);
      final pos = feed(t,
          'bienvenido a la demostracion hoy vamos hablar de teleprompter libre para windows y android');
      expect(pos, equals(t.sourceText.length));
    });

    test('no salta lejos con palabras ajenas', () {
      final t = SpeechTracker()..reset(script);
      feed(t, 'patata zanahoria cebolla');
      // Como en Textream, sólo se permiten pasos pequeños sin confirmación.
      expect(t.recognizedCharCount, lessThanOrEqualTo(15));
    });

    test('saltar a una palabra y continuar', () {
      final t = SpeechTracker()..reset(script);
      final idx = t.sourceText.indexOf('Windows');
      t.jumpTo(idx);
      t.beginNewTranscript();
      final pos = feed(t, 'windows y android');
      expect(pos, equals(t.sourceText.length));
    });

    test('modo director conserva el progreso', () {
      final t = SpeechTracker()..reset('uno dos tres');
      feed(t, 'uno dos');
      final before = t.recognizedCharCount;
      t.updateText('uno dos tres cuatro cinco', before);
      expect(t.recognizedCharCount, equals(before));
    });
  });

  group('actividad de voz', () {
    test('activa con voz y se apaga tras el silencio', () {
      final vad = VoiceActivityDetector();
      vad.process(0.05, 0);
      expect(vad.isActive(100), isTrue);
      expect(vad.isActive(800), isFalse);
      vad.process(0.001, 990); // silencio: reinicia el contador
      vad.process(0.02, 1000);
      expect(vad.isActive(1001), isFalse);
      vad.process(0.02, 1050);
      expect(vad.isActive(1100), isTrue);
    });

    test('RMS de PCM16', () {
      final b = ByteData(4)
        ..setInt16(0, 16384, Endian.little)
        ..setInt16(2, -16384, Endian.little);
      expect(rmsLevelPcm16(b.buffer.asUint8List()), closeTo(0.5, 0.001));
    });
  });

  group('PowerPoint', () {
    test('extrae notas del presentador', () {
      final bytes = File('test/fixtures/notes.pptx').readAsBytesSync();
      final pages = extractPptxNotes(bytes);
      expect(pages.length, equals(2));
      expect(pages[0], equals('Hola a todos, bienvenidos.\nSegunda línea & más'));
      expect(pages[1], equals('Gracias por venir <3'));
    });
  });
}
