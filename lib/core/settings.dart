import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum GuidanceMode { wordTracking, classic, voiceActivated }

enum OverlayMode { pinnedTop, floating, fullscreen }

enum MirrorMode { none, horizontal, vertical, both }

enum PromptFont { sans, serif, mono, dyslexic }

const guidanceLabels = {
  GuidanceMode.wordTracking: 'Seguimiento de palabras',
  GuidanceMode.classic: 'Clásico (velocidad fija)',
  GuidanceMode.voiceActivated: 'Activado por voz',
};

const overlayLabels = {
  OverlayMode.pinnedTop: 'Isla superior (fija arriba)',
  OverlayMode.floating: 'Ventana flotante',
  OverlayMode.fullscreen: 'Pantalla completa',
};

const mirrorLabels = {
  MirrorMode.none: 'Sin espejo',
  MirrorMode.horizontal: 'Horizontal',
  MirrorMode.vertical: 'Vertical',
  MirrorMode.both: 'Ambos (180°)',
};

const fontLabels = {
  PromptFont.sans: 'Sans',
  PromptFont.serif: 'Serif',
  PromptFont.mono: 'Mono',
  PromptFont.dyslexic: 'OpenDyslexic',
};

const highlightColors = <String, Color>{
  'Blanco': Color(0xFFFFFFFF),
  'Amarillo': Color(0xFFFFD60A),
  'Verde': Color(0xFF30D158),
  'Azul': Color(0xFF64D2FF),
  'Rosa': Color(0xFFFF6482),
  'Naranja': Color(0xFFFF9F0A),
};

String? fontFamilyFor(PromptFont f) => switch (f) {
      PromptFont.sans => null,
      PromptFont.serif => 'serif',
      PromptFont.mono => 'monospace',
      PromptFont.dyslexic => 'OpenDyslexic',
    };

List<String>? fontFallbackFor(PromptFont f) => switch (f) {
      PromptFont.serif => const ['Georgia', 'Times New Roman', 'Noto Serif'],
      PromptFont.mono => const ['Consolas', 'Cascadia Mono', 'Roboto Mono'],
      _ => null,
    };

/// Almacén de ajustes: SharedPreferences en la app, memoria en la ventana
/// flotante de Android (que corre en un motor aparte).
abstract class SettingsStore {
  Object? get(String key);
  void set(String key, Object value);

  String? getString(String k) => get(k) as String?;
  double? getDouble(String k) => (get(k) as num?)?.toDouble();
  bool? getBool(String k) => get(k) as bool?;
  int? getInt(String k) => (get(k) as num?)?.toInt();
  List<String>? getStringList(String k) => (get(k) as List?)?.cast<String>();
  void setString(String k, String v) => set(k, v);
  void setDouble(String k, double v) => set(k, v);
  void setBool(String k, bool v) => set(k, v);
  void setInt(String k, int v) => set(k, v);
  void setStringList(String k, List<String> v) => set(k, v);
}

class _PrefsStore extends SettingsStore {
  _PrefsStore(this.prefs);
  final SharedPreferences prefs;

  @override
  Object? get(String key) => prefs.get(key);

  @override
  void set(String key, Object value) {
    switch (value) {
      case String v:
        prefs.setString(key, v);
      case bool v:
        prefs.setBool(key, v);
      case int v:
        prefs.setInt(key, v);
      case double v:
        prefs.setDouble(key, v);
      case List v:
        prefs.setStringList(key, v.cast<String>());
    }
  }
}

class MemoryStore extends SettingsStore {
  MemoryStore([Map<String, Object?>? initial]) : values = {...?initial};
  final Map<String, Object?> values;

  @override
  Object? get(String key) => values[key];

  @override
  void set(String key, Object value) => values[key] = value;
}

class AppSettings extends ChangeNotifier {
  AppSettings._(this._prefs);
  AppSettings.memory([Map<String, Object?>? values])
      : _prefs = MemoryStore(values);
  final SettingsStore _prefs;

  static Future<AppSettings> load() async {
    final prefs = await SharedPreferences.getInstance();
    return AppSettings._(_PrefsStore(prefs));
  }

  /// Copia de los ajustes visuales para la ventana flotante.
  Map<String, Object?> exportVisual() => {
        for (final k in const [
          'speed',
          'font',
          'fontSize',
          'highlight',
          'mirror',
          'floatHeight',
          'floatLines',
        ])
          if (_prefs.get(k) != null) k: _prefs.get(k),
      };

  T _enum<T extends Enum>(String key, List<T> values, T def) {
    final name = _prefs.getString(key);
    return values.firstWhere((v) => v.name == name, orElse: () => def);
  }

  void _setEnum(String key, Enum v) {
    _prefs.setString(key, v.name);
    notifyListeners();
  }

  double _d(String k, double def) => _prefs.getDouble(k) ?? def;
  void _setD(String k, double v) {
    _prefs.setDouble(k, v);
    notifyListeners();
  }

  bool _b(String k, bool def) => _prefs.getBool(k) ?? def;
  void _setB(String k, bool v) {
    _prefs.setBool(k, v);
    notifyListeners();
  }

  int _i(String k, int def) => _prefs.getInt(k) ?? def;
  void _setI(String k, int v) {
    _prefs.setInt(k, v);
    notifyListeners();
  }

  // Guía
  GuidanceMode get guidance =>
      _enum('guidance', GuidanceMode.values, GuidanceMode.wordTracking);
  set guidance(GuidanceMode v) => _setEnum('guidance', v);

  double get speed => _d('speed', 2.5); // palabras por segundo
  set speed(double v) => _setD('speed', v);

  String get speechLocale => _prefs.getString('speechLocale') ?? '';
  set speechLocale(String v) {
    _prefs.setString('speechLocale', v);
    notifyListeners();
  }

  // Ventana (Windows)
  OverlayMode get overlay =>
      _enum('overlay', OverlayMode.values, OverlayMode.pinnedTop);
  set overlay(OverlayMode v) => _setEnum('overlay', v);

  double get overlayWidth => _d('overlayWidth', 460);
  set overlayWidth(double v) => _setD('overlayWidth', v);

  double get overlayHeight => _d('overlayHeight', 180);
  set overlayHeight(double v) => _setD('overlayHeight', v);

  double get glassOpacity => _d('glassOpacity', 0.85);
  set glassOpacity(double v) => _setD('glassOpacity', v);

  bool get hideFromCapture => _b('hideFromCapture', false);
  set hideFromCapture(bool v) => _setB('hideFromCapture', v);

  int get displayIndex => _i('displayIndex', 0);
  set displayIndex(int v) => _setI('displayIndex', v);

  // Texto
  PromptFont get font => _enum('font', PromptFont.values, PromptFont.sans);
  set font(PromptFont v) => _setEnum('font', v);

  double get fontSize => _d('fontSize', 26);
  set fontSize(double v) => _setD('fontSize', v);

  String get highlightName => _prefs.getString('highlight') ?? 'Amarillo';
  set highlightName(String v) {
    _prefs.setString('highlight', v);
    notifyListeners();
  }

  Color get highlightColor =>
      highlightColors[highlightName] ?? highlightColors['Amarillo']!;

  MirrorMode get mirror => _enum('mirror', MirrorMode.values, MirrorMode.none);
  set mirror(MirrorMode v) => _setEnum('mirror', v);

  /// true = línea activa arriba (cerca de la cámara), false = centrada.
  bool get readingLineTop => _b('readingLineTop', true);
  set readingLineTop(bool v) => _setB('readingLineTop', v);

  bool get autoAdvancePages => _b('autoAdvance', true);
  set autoAdvancePages(bool v) => _setB('autoAdvance', v);

  // Android: franja de lectura junto a la cámara frontal
  /// true = el texto ocupa una franja estrecha arriba, pegada a la cámara.
  bool get phoneBand => _b('phoneBand', true);
  set phoneBand(bool v) => _setB('phoneBand', v);

  /// Líneas visibles en la franja.
  double get bandLines => _d('bandLines', 3);
  set bandLines(double v) => _setD('bandLines', v);

  /// Ancho de la franja (fracción de la pantalla), centrada bajo la cámara.
  double get bandWidth => _d('bandWidth', 0.8);
  set bandWidth(double v) => _setD('bandWidth', v);

  /// Ventana flotante de Android: líneas de texto visibles.
  double get floatLines => _d('floatLines', 3);
  set floatLines(double v) => _setD('floatLines', v);

  // Remoto / Director
  bool get remoteEnabled => _b('remoteEnabled', false);
  set remoteEnabled(bool v) => _setB('remoteEnabled', v);

  int get remotePort => _i('remotePort', 7373);
  set remotePort(int v) => _setI('remotePort', v);

  bool get directorEnabled => _b('directorEnabled', false);
  set directorEnabled(bool v) => _setB('directorEnabled', v);

  int get directorPort => _i('directorPort', 7575);
  set directorPort(int v) => _setI('directorPort', v);

  // Guion autoguardado
  List<String> get savedPages => _prefs.getStringList('pages') ?? const [''];
  set savedPages(List<String> v) => _prefs.setStringList('pages', v);
}
