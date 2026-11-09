// Control de la ventana en Windows: isla superior, flotante "siempre encima",
// pantalla completa en el monitor elegido y ocultar de capturas de pantalla.

import 'dart:ffi' hide Size;
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:screen_retriever/screen_retriever.dart';
import 'package:window_manager/window_manager.dart';

import '../core/settings.dart';

bool get isDesktop =>
    Platform.isWindows || Platform.isLinux || Platform.isMacOS;

class WindowService {
  WindowService._();
  static final instance = WindowService._();

  Rect? _savedBounds;
  bool _overlayActive = false;

  static Future<void> init() async {
    if (!isDesktop) return;
    await windowManager.ensureInitialized();
    const options = WindowOptions(
      size: Size(980, 680),
      minimumSize: Size(260, 90),
      center: true,
      title: 'Teleponter',
    );
    await windowManager.waitUntilReadyToShow(options, () async {
      await windowManager.show();
      await windowManager.focus();
    });
  }

  Future<List<Display>> displays() async {
    if (!isDesktop) return const [];
    try {
      return await screenRetriever.getAllDisplays();
    } catch (_) {
      return const [];
    }
  }

  Future<void> enterPrompter(AppSettings s) async {
    if (!isDesktop) return;
    _savedBounds ??= await windowManager.getBounds();
    _overlayActive = true;
    await applyCaptureProtection(s.hideFromCapture);

    switch (s.overlay) {
      case OverlayMode.fullscreen:
        final list = await displays();
        if (list.isNotEmpty) {
          final d = list[s.displayIndex.clamp(0, list.length - 1)];
          final pos = d.visiblePosition ?? Offset.zero;
          await windowManager.setPosition(pos + const Offset(40, 40));
        }
        await windowManager.setAlwaysOnTop(true);
        await windowManager.setFullScreen(true);
      case OverlayMode.pinnedTop:
      case OverlayMode.floating:
        await windowManager.setTitleBarStyle(TitleBarStyle.hidden,
            windowButtonVisibility: false);
        await windowManager.setAlwaysOnTop(true);
        await windowManager.setSkipTaskbar(false);
        final size = Size(s.overlayWidth, s.overlayHeight + 44);
        await windowManager.setMinimumSize(const Size(260, 90));
        await windowManager.setSize(size);
        // Transparencia real de la ventana (efecto cristal).
        await windowManager.setOpacity(s.glassOpacity.clamp(0.4, 1.0));
        if (s.overlay == OverlayMode.pinnedTop) {
          final primary = await screenRetriever.getPrimaryDisplay();
          final origin = primary.visiblePosition ?? Offset.zero;
          final area = primary.visibleSize ?? primary.size;
          await windowManager.setPosition(Offset(
            origin.dx + (area.width - size.width) / 2,
            origin.dy,
          ));
        }
    }
  }

  Future<void> exitPrompter() async {
    if (!isDesktop || !_overlayActive) return;
    _overlayActive = false;
    if (await windowManager.isFullScreen()) {
      await windowManager.setFullScreen(false);
    }
    await windowManager.setAlwaysOnTop(false);
    await windowManager.setOpacity(1);
    await windowManager.setTitleBarStyle(TitleBarStyle.normal);
    await windowManager.setMinimumSize(const Size(260, 90));
    if (_savedBounds != null) {
      await windowManager.setBounds(_savedBounds);
      _savedBounds = null;
    }
    await applyCaptureProtection(false);
  }

  Future<void> startDragging() async {
    if (isDesktop) await windowManager.startDragging();
  }

  /// Excluye la ventana de grabaciones y videollamadas (Windows 10 2004+).
  Future<void> applyCaptureProtection(bool hide) async {
    if (!Platform.isWindows) return;
    try {
      _Win32.setExcludeFromCapture(hide);
    } catch (_) {}
  }
}

typedef _EnumProcNative = Int32 Function(IntPtr hwnd, IntPtr lParam);

class _Win32 {
  static final DynamicLibrary _user32 = DynamicLibrary.open('user32.dll');
  static final DynamicLibrary _kernel32 = DynamicLibrary.open('kernel32.dll');

  static final int Function(Pointer<NativeFunction<_EnumProcNative>>, int)
      _enumWindows = _user32.lookupFunction<
          Int32 Function(Pointer<NativeFunction<_EnumProcNative>>, IntPtr),
          int Function(Pointer<NativeFunction<_EnumProcNative>>, int)>(
    'EnumWindows',
  );
  static final int Function(int, Pointer<Uint32>) _getWindowThreadProcessId =
      _user32.lookupFunction<Uint32 Function(IntPtr, Pointer<Uint32>),
          int Function(int, Pointer<Uint32>)>('GetWindowThreadProcessId');
  static final int Function(int) _isWindowVisible =
      _user32.lookupFunction<Int32 Function(IntPtr), int Function(int)>(
          'IsWindowVisible');
  static final int Function(int, int) _setWindowDisplayAffinity = _user32
      .lookupFunction<Int32 Function(IntPtr, Uint32), int Function(int, int)>(
          'SetWindowDisplayAffinity');
  static final int Function(int, int) _localAlloc = _kernel32.lookupFunction<
      IntPtr Function(Uint32, IntPtr), int Function(int, int)>('LocalAlloc');
  static final int Function(int) _localFree = _kernel32
      .lookupFunction<IntPtr Function(IntPtr), int Function(int)>('LocalFree');

  static final List<int> _found = [];
  static Pointer<Uint32> _pidBuf = nullptr;

  static int _enumProc(int hwnd, int lParam) {
    _getWindowThreadProcessId(hwnd, _pidBuf);
    if (_pidBuf.value == pid && _isWindowVisible(hwnd) != 0) _found.add(hwnd);
    return 1;
  }

  static void setExcludeFromCapture(bool hide) {
    const wdaNone = 0x0;
    const wdaExcludeFromCapture = 0x11;
    final mem = _localAlloc(0x40, 4); // LPTR
    _pidBuf = Pointer<Uint32>.fromAddress(mem);
    _found.clear();
    try {
      _enumWindows(Pointer.fromFunction<_EnumProcNative>(_enumProc, 0), 0);
      for (final hwnd in _found) {
        _setWindowDisplayAffinity(hwnd, hide ? wdaExcludeFromCapture : wdaNone);
      }
    } finally {
      _localFree(mem);
      _pidBuf = nullptr;
    }
  }
}
