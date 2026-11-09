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
  }) async {
    _ensureListening();
    _pending = {
      'type': 'script',
      'pages': pages,
      'page': pageIndex,
      'settings': settings.exportVisual(),
    };
    if (await FlutterOverlayWindow.isActive()) {
      await FlutterOverlayWindow.shareData(_pending);
      return;
    }
    final lines = settings.floatLines.clamp(1, 12);
    final height = (settings.fontSize * 1.35 * lines + 52).round();
    await FlutterOverlayWindow.showOverlay(
      height: height,
      width: WindowSize.matchParent,
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
