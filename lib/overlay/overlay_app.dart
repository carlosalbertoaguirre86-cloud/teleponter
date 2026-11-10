// Interfaz de la ventana flotante de Android. Corre en un motor de Flutter
// aparte (entrada `overlayMain` en main.dart), así que recibe el guion y
// los ajustes desde la app principal por mensajes.
//
// Sólo usa el modo clásico (velocidad fija): mientras otra app graba vídeo,
// Android le da el micrófono a esa app y no a Teleponter.

import 'package:flutter/material.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';

import '../core/settings.dart';
import '../services/prompter_controller.dart';
import '../ui/prompter_text.dart';

void runOverlayApp() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MaterialApp(
    debugShowCheckedModeBanner: false,
    home: _OverlayPrompter(),
  ));
}

class _OverlayPrompter extends StatefulWidget {
  const _OverlayPrompter();

  @override
  State<_OverlayPrompter> createState() => _OverlayPrompterState();
}

class _OverlayPrompterState extends State<_OverlayPrompter> {
  AppSettings? _settings;
  PrompterController? _c;
  String _lastKey = '';
  double _designH = 0; // alto previsto en dp
  double _designW = 0;
  int _resizeTries = 0;

  @override
  void initState() {
    super.initState();
    FlutterOverlayWindow.overlayListener.listen(_onMessage);
    FlutterOverlayWindow.shareData({'type': 'ready'});
  }

  Future<void> _onMessage(dynamic msg) async {
    if (msg is! Map || msg['type'] != 'script') return;
    final pages = (msg['pages'] as List).map((e) => e.toString()).toList();
    final page = (msg['page'] as num?)?.toInt() ?? 0;
    final key = '${pages.join('\u0000')}|$page';
    if (key == _lastKey) return; // mensaje repetido
    _lastKey = key;

    final values = Map<String, Object?>.from(
        (msg['settings'] as Map?)?.cast<String, Object?>() ?? const {});
    final settings = AppSettings.memory(values)
      ..guidance = GuidanceMode.classic
      ..autoAdvancePages = true;
    final old = _c;
    final c = PrompterController(settings)
      ..pages = pages.isEmpty ? [''] : pages;
    await old?.stop();
    old?.dispose();
    setState(() {
      _settings = settings;
      _c = c;
      _designH = (msg['height'] as num?)?.toDouble() ?? 0;
      _designW = (msg['width'] as num?)?.toDouble() ?? 0;
      _resizeTries = 0;
    });
    // Empieza en pausa: pulsa ▶ cuando estés listo para grabar.
    await c.start(fromPage: page);
  }

  Future<void> _close() async {
    await _c?.stop();
    await FlutterOverlayWindow.closeOverlay();
  }

  @override
  Widget build(BuildContext context) {
    final c = _c;
    final s = _settings;
    // En algunos móviles el motor de la ventana flotante no recibe la
    // densidad de pantalla y todo se ve diminuto. Si el espacio real es
    // mucho mayor que el previsto, se escala el contenido para llenarlo.
    return LayoutBuilder(builder: (context, box) {
      var scale = 1.0;
      if (_designH > 0 && box.maxHeight.isFinite) {
        final r = box.maxHeight / _designH;
        if (r > 1.3 || r < 0.75) scale = r;
      }
      // En algunos móviles (p. ej. Samsung con zoom de pantalla) la ventana
      // sale más pequeña de lo pedido: se corrige su tamaño real una vez.
      if (scale != 1.0 && _resizeTries < 2 && _designW > 0) {
        _resizeTries++;
        final w = _designW / scale, h = _designH / scale;
        WidgetsBinding.instance.addPostFrameCallback((_) async {
          var width = w;
          try {
            final screen = await FlutterOverlayWindow.getScreenSize();
            if (screen.x > 0) width = width.clamp(120, screen.x).toDouble();
          } catch (_) {}
          await FlutterOverlayWindow.resizeOverlay(
              width.round(), h.round(), true);
        });
      }
      final content = _content(c, s);
      if (scale == 1.0) return content;
      return FittedBox(
        fit: BoxFit.fill,
        child: SizedBox(
          width: box.maxWidth / scale,
          height: box.maxHeight / scale,
          child: content,
        ),
      );
    });
  }

  Widget _content(PrompterController? c, AppSettings? s) {
    return Material(
      color: Colors.transparent,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(18),
        ),
        clipBehavior: Clip.antiAlias,
        child: c == null || s == null
            ? const Center(
                child: Text('Cargando guion…',
                    style: TextStyle(color: Colors.white54)))
            : ListenableBuilder(
                listenable: Listenable.merge([c, s]),
                builder: (context, _) => Column(children: [
                  Expanded(
                    child: PrompterText(
                      controller: c,
                      compact: true,
                      fontScale: 1 / 0.75,
                      anchor: 6,
                      overCamera: true,
                    ),
                  ),
                  SizedBox(height: 44, child: _controls(c, s)),
                ]),
              ),
      ),
    );
  }

  Widget _controls(PrompterController c, AppSettings s) {
    Widget btn(IconData icon, VoidCallback? onTap, {Color? color}) =>
        IconButton(
          icon: Icon(icon, size: 20, color: color ?? Colors.white),
          onPressed: onTap,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
        );
    return Column(children: [
      ClipRRect(
        borderRadius: BorderRadius.circular(2),
        child: LinearProgressIndicator(
          value: c.progress,
          minHeight: 3,
          backgroundColor: Colors.white12,
          color: s.highlightColor,
        ),
      ),
      Expanded(
        child: Center(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              btn(Icons.close, _close, color: Colors.redAccent),
              btn(Icons.replay, () => c.restart(play: false)),
              btn(Icons.fast_rewind, () => c.skipWords(-6)),
              btn((c.paused || c.done) ? Icons.play_arrow : Icons.pause,
                  c.togglePause,
                  color: (c.paused || c.done) ? s.highlightColor : null),
              btn(Icons.fast_forward, () => c.skipWords(6)),
              btn(Icons.remove, () => c.setSpeed(s.speed - 0.25)),
              Text(s.speed.toStringAsFixed(1),
                  style: const TextStyle(color: Colors.white70, fontSize: 12)),
              btn(Icons.add, () => c.setSpeed(s.speed + 0.25)),
              btn(Icons.text_decrease,
                  () => s.fontSize = (s.fontSize - 2).clamp(14, 72)),
              btn(Icons.text_increase,
                  () => s.fontSize = (s.fontSize + 2).clamp(14, 72)),
            ]),
          ),
        ),
      ),
    ]);
  }
}
