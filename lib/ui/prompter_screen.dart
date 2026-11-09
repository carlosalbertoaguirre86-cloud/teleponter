// Pantalla de lectura: modo compacto (isla / flotante en Windows) o
// completo (pantalla completa, Android), con cámara opcional.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/settings.dart';
import '../services/prompter_controller.dart';
import '../services/window_service.dart';
import 'camera_layer.dart';
import 'prompter_text.dart';

class PrompterScreen extends StatefulWidget {
  const PrompterScreen({
    super.key,
    required this.controller,
    this.recordMode = false,
  });

  final PrompterController controller;

  /// Android: grabar vídeo con la cámara mientras se lee.
  final bool recordMode;

  @override
  State<PrompterScreen> createState() => _PrompterScreenState();
}

class _PrompterScreenState extends State<PrompterScreen> {
  PrompterController get c => widget.controller;
  AppSettings get s => c.settings;
  CameraLayerController? _camera;
  bool _closing = false;
  bool _showCamera = false;
  late bool _compact;

  @override
  void initState() {
    super.initState();
    _compact = isDesktop && s.overlay != OverlayMode.fullscreen;
    c.onFinished = _close;
    if (widget.recordMode) _toggleCamera();
    if (!isDesktop) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    }
  }

  @override
  void dispose() {
    if (c.onFinished == _close) c.onFinished = null;
    _camera?.dispose();
    if (!isDesktop) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }
    super.dispose();
  }

  Future<void> _toggleCamera() async {
    if (_camera == null) {
      final cam = CameraLayerController();
      setState(() {
        _camera = cam;
        _showCamera = true;
      });
      await cam.init();
    } else if (!(_camera!.recording)) {
      final cam = _camera;
      setState(() {
        _camera = null;
        _showCamera = false;
      });
      cam?.dispose();
    }
  }

  Future<void> _close() async {
    if (_closing) return;
    _closing = true;
    if (_camera?.recording ?? false) await _camera!.toggleRecording();
    await c.stop();
    await WindowService.instance.exitPrompter();
    if (mounted) Navigator.of(context).maybePop();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    if (e is! KeyDownEvent) return KeyEventResult.ignored;
    final k = e.logicalKey;
    if (k == LogicalKeyboardKey.escape) {
      _close();
    } else if (k == LogicalKeyboardKey.space) {
      c.togglePause();
    } else if (k == LogicalKeyboardKey.arrowUp) {
      c.setSpeed(s.speed + 0.5);
    } else if (k == LogicalKeyboardKey.arrowDown) {
      c.setSpeed(s.speed - 0.5);
    } else if (k == LogicalKeyboardKey.arrowRight ||
        k == LogicalKeyboardKey.pageDown) {
      c.nextPage();
    } else if (k == LogicalKeyboardKey.arrowLeft ||
        k == LogicalKeyboardKey.pageUp) {
      c.previousPage();
    } else if (k == LogicalKeyboardKey.keyM) {
      c.toggleMute();
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _closing,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _close();
      },
      child: Focus(
        autofocus: true,
        onKeyEvent: _onKey,
        child: ListenableBuilder(
          listenable: Listenable.merge([c, s]),
          builder: (context, _) =>
              _compact ? _buildCompact(context) : _buildFull(context),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------
  // Compacto (Windows: isla superior / ventana flotante)

  Widget _buildCompact(BuildContext context) {
    final pinned = s.overlay == OverlayMode.pinnedTop;
    return Scaffold(
      backgroundColor: Colors.black,
      body: Container(
        decoration: BoxDecoration(
          color: Colors.black,
          borderRadius: pinned
              ? const BorderRadius.vertical(bottom: Radius.circular(22))
              : BorderRadius.circular(16),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            Expanded(
              child: Stack(children: [
                Positioned.fill(
                    child: PrompterText(controller: c, compact: true)),
                _overlays(),
              ]),
            ),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onPanStart: (_) => WindowService.instance.startDragging(),
              child: SizedBox(
                height: 40,
                child: Row(children: [
                  const SizedBox(width: 10),
                  Waveform(levels: c.levels, active: c.isListening),
                  const SizedBox(width: 8),
                  Expanded(child: _progress()),
                  ..._controls(compact: true),
                ]),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------
  // Completo (pantalla completa / Android)

  Widget _buildFull(BuildContext context) {
    final cam = _camera;
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          if (_showCamera && cam != null)
            Positioned.fill(
              child: Opacity(
                opacity: 1,
                child: CameraPreviewLayer(controller: cam),
              ),
            ),
          if (_showCamera)
            Positioned.fill(
                child: Container(color: Colors.black.withValues(alpha: 0.45))),
          SafeArea(
            child: Column(
              children: [
                Expanded(
                  child: Stack(children: [
                    Positioned.fill(
                      child: PrompterText(
                        controller: c,
                        overCamera: _showCamera,
                      ),
                    ),
                    _overlays(),
                  ]),
                ),
                Container(
                  color: _showCamera ? Colors.black54 : const Color(0xFF111113),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Row(children: [
                      Waveform(levels: c.levels, active: c.isListening),
                      const SizedBox(width: 10),
                      Expanded(child: _progress()),
                      const SizedBox(width: 10),
                      Text(
                        c.pages.length > 1
                            ? 'Pág. ${c.pageIndex + 1}/${c.pages.length}'
                            : guidanceLabels[c.mode]!,
                        style: const TextStyle(
                            color: Colors.white54, fontSize: 12),
                      ),
                    ]),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(children: _controls(compact: false)),
                    ),
                  ]),
                ),
              ],
            ),
          ),
          if (cam != null) _recordButton(cam),
        ],
      ),
    );
  }

  Widget _recordButton(CameraLayerController cam) {
    return Positioned(
      right: 16,
      top: MediaQuery.paddingOf(context).top + 16,
      child: ListenableBuilder(
        listenable: cam,
        builder: (context, _) {
          if (cam.message != null) {
            final msg = cam.message!;
            cam.message = null;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) {
                ScaffoldMessenger.of(context)
                    .showSnackBar(SnackBar(content: Text(msg)));
              }
            });
          }
          return Column(children: [
            FloatingActionButton(
              heroTag: 'rec',
              backgroundColor: cam.recording ? Colors.white : Colors.red,
              onPressed: cam.ready ? cam.toggleRecording : null,
              tooltip: cam.recording ? 'Detener grabación' : 'Grabar vídeo',
              child: cam.busy
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : Icon(cam.recording ? Icons.stop : Icons.fiber_manual_record,
                      color: cam.recording ? Colors.red : Colors.white),
            ),
            const SizedBox(height: 12),
            if (cam.canSwitch)
              FloatingActionButton.small(
                heroTag: 'flip',
                backgroundColor: Colors.black54,
                onPressed: cam.switchCamera,
                tooltip: 'Cambiar cámara',
                child: const Icon(Icons.cameraswitch, color: Colors.white),
              ),
          ]);
        },
      ),
    );
  }

  Widget _progress() => ClipRRect(
        borderRadius: BorderRadius.circular(2),
        child: LinearProgressIndicator(
          value: c.progress,
          minHeight: 4,
          backgroundColor: Colors.white12,
          color: s.highlightColor,
        ),
      );

  Widget _overlays() {
    return Positioned.fill(
      child: IgnorePointer(
        ignoring: c.countdown == null && c.error == null,
        child: Stack(children: [
          if (c.countdown != null)
            Center(
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.black87,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Text('Siguiente página en ${c.countdown}…',
                      style:
                          const TextStyle(color: Colors.white, fontSize: 16)),
                  TextButton(
                    onPressed: c.nextPage,
                    child: const Text('Ahora'),
                  ),
                ]),
              ),
            ),
          if (c.error != null)
            Align(
              alignment: Alignment.topCenter,
              child: Container(
                margin: const EdgeInsets.all(8),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.red.shade900.withValues(alpha: 0.9),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(c.error!,
                    style: const TextStyle(color: Colors.white, fontSize: 12)),
              ),
            ),
        ]),
      ),
    );
  }

  List<Widget> _controls({required bool compact}) {
    final size = compact ? 18.0 : 24.0;
    final usesSpeed = c.mode != GuidanceMode.wordTracking;
    Widget btn(IconData icon, String tip, VoidCallback? onTap,
            {Color? color}) =>
        IconButton(
          icon: Icon(icon, size: size, color: color ?? Colors.white),
          tooltip: tip,
          onPressed: onTap,
          visualDensity: compact ? VisualDensity.compact : null,
          padding: compact ? EdgeInsets.zero : const EdgeInsets.all(8),
          constraints: compact
              ? const BoxConstraints(minWidth: 30, minHeight: 30)
              : null,
        );
    return [
      if (c.pages.length > 1)
        btn(Icons.skip_previous, 'Página anterior', c.previousPage),
      btn(c.paused ? Icons.play_arrow : Icons.pause,
          c.paused ? 'Reanudar (Espacio)' : 'Pausa (Espacio)', c.togglePause),
      if (c.pages.length > 1)
        btn(Icons.skip_next, 'Página siguiente',
            c.hasNextPage ? c.nextPage : null),
      if (c.usesMicrophone)
        btn(c.muted ? Icons.mic_off : Icons.mic,
            c.muted ? 'Activar micrófono (M)' : 'Silenciar (M)', c.toggleMute,
            color: c.muted ? Colors.redAccent : null),
      if (usesSpeed) ...[
        btn(Icons.remove, 'Más lento (↓)', () => c.setSpeed(s.speed - 0.5)),
        Text('${s.speed.toStringAsFixed(1)} p/s',
            style:
                TextStyle(color: Colors.white70, fontSize: compact ? 11 : 13)),
        btn(Icons.add, 'Más rápido (↑)', () => c.setSpeed(s.speed + 0.5)),
      ],
      if (!compact) ...[
        btn(Icons.flip, 'Espejo', () {
          s.mirror = s.mirror == MirrorMode.none
              ? MirrorMode.horizontal
              : MirrorMode.none;
        }, color: s.mirror != MirrorMode.none ? s.highlightColor : null),
        btn(Icons.text_decrease, 'Texto más pequeño',
            () => s.fontSize = (s.fontSize - 2).clamp(14, 96)),
        btn(Icons.text_increase, 'Texto más grande',
            () => s.fontSize = (s.fontSize + 2).clamp(14, 96)),
        if (Platform.isAndroid)
          btn(_showCamera ? Icons.videocam_off : Icons.videocam,
              _showCamera ? 'Ocultar cámara' : 'Mostrar cámara', _toggleCamera),
      ],
      btn(Icons.close, 'Cerrar (Esc)', _close),
      if (compact) const SizedBox(width: 6),
    ];
  }
}

class Waveform extends StatelessWidget {
  const Waveform({super.key, required this.levels, required this.active});
  final List<double> levels;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: active ? 1 : 0.3,
      child: SizedBox(
        height: 22,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final l in levels.skip(levels.length - 16))
              Container(
                width: 3,
                height: (2 + l * 20).clamp(2.0, 22.0),
                margin: const EdgeInsets.symmetric(horizontal: 1),
                decoration: BoxDecoration(
                  color: const Color(0xFF30D158),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
