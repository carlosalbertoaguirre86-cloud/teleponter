// Android: ventana flotante del teleprompter encima de otras apps
// (cámara, Instagram, TikTok, Zoom...). Usa el permiso
// "Mostrar sobre otras apps".

import 'dart:async';

import 'package:flutter_overlay_window/flutter_overlay_window.dart';

import '../core/settings.dart';

class FloatingService {
  FloatingService._();

  static Stream<dynamic>? _events;
  static Map<String, Object?>? _pending;

  /// Escucha los mensajes de la ventana flotante (una sola suscripción).
  static Stream<dynamic> get events =>
      _events ??= FlutterOverlayWindow.overlayListener.asBroadcastStream();

  static bool _listening = false;

  static void _ensureListening() {
    if (_listening) return;
    _listening = true;
    events.listen((msg) {
      // La ventana avisa cuando está lista para recibir el guion.
      if (msg is Map && msg['type'] == 'ready' && _pending != null) {
        FlutterOverlayWindow.shareData(_pending);
      }
    });
  }

  static Future<bool> hasPermission() =>
      FlutterOverlayWindow.isPermissionGranted();

  static Future<bool> requestPermission() async {
    try {
      return await FlutterOverlayWindow.requestPermission() ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> isActive() => FlutterOverlayWindow.isActive();

  static Future<void> close() => FlutterOverlayWindow.closeOverlay();

  /// Abre la ventana flotante arriba, junto a la cámara frontal.
  static Future<void> show({
    required AppSettings settings,
    required List<String> pages,
    required int pageIndex,
    required double screenWidth,
    required double pixelRatio,
  }) async {
    // Mismo tamaño que la franja de la app: ancho y líneas de Ajustes.
    final k = settings.floatScale.clamp(0.5, 2.5);
    // Al agrandar, la ventana también gana ancho (hasta el de la pantalla).
    final widthDp = (screenWidth * settings.bandWidth.clamp(0.4, 1.0) * k)
        .clamp(160.0, screenWidth)
        .round();
    final fontSize = settings.fontSize * k;
    final heightDp =
        (fontSize * 1.35 * settings.bandLines.clamp(1, 12) + 14 + 46).round();
    _ensureListening();
    _pending = {
      'type': 'script',
      'pages': pages,
      'page': pageIndex,
      'settings': {...settings.exportVisual(), 'fontSize': fontSize},
      'width': widthDp,
      'height': heightDp,
    };
    if (await FlutterOverlayWindow.isActive()) {
      await FlutterOverlayWindow.shareData(_pending);
      return;
    }
    // OJO: aunque la documentación diga "dp", showOverlay crea la ventana
    // con el valor en PÍXELES físicos (sólo resizeOverlay convierte).
    // Por eso la ventana salía 3 veces más pequeña: se convierte aquí.
    await FlutterOverlayWindow.showOverlay(
      height: (heightDp * pixelRatio).round(),
      width: (widthDp * pixelRatio).round(),
      alignment: OverlayAlignment.topCenter,
      flag: OverlayFlag.defaultFlag,
      enableDrag: true,
      positionGravity: PositionGravity.none,
      overlayTitle: 'Teleponter',
      overlayContent: 'Teleprompter flotante activo',
    );
    // Por si el aviso "ready" llegó antes de tiempo.
    Timer(const Duration(milliseconds: 1200), () {
      if (_pending != null) FlutterOverlayWindow.shareData(_pending);
    });
  }
}
