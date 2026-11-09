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
    c.onFinished = () => c.togglePause();
    await old?.stop();
    old?.dispose();
    setState(() {
      _settings = settings;
      _c = c;
    });
    await c.start(fromPage: page);
    // Empieza en pausa: pulsa ▶ cuando estés listo para grabar.
    await c.togglePause();
  }

  Future<void> _close() async {
    await _c?.stop();
    await FlutterOverlayWindow.closeOverlay();
  }

  @override
  Widget build(BuildContext context) {
    final c = _c;
    final s = _settings;
    return Material(
      color: Colors.transparent,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.85),
          borderRadius: BorderRadius.circular(16),
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
                      anchor: 4,
                    ),
                  ),
                  SizedBox(height: 40, child: _controls(c, s)),
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
    return Row(children: [
      const SizedBox(width: 6),
      Expanded(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(2),
          child: LinearProgressIndicator(
            value: c.progress,
            minHeight: 3,
            backgroundColor: Colors.white12,
            color: s.highlightColor,
          ),
        ),
      ),
      if (c.pages.length > 1) btn(Icons.skip_previous, c.previousPage),
      btn(c.paused ? Icons.play_arrow : Icons.pause, c.togglePause,
          color: c.paused ? s.highlightColor : null),
      if (c.pages.length > 1) btn(Icons.skip_next, c.nextPage),
      btn(Icons.remove, () => c.setSpeed(s.speed - 0.25)),
      Text(s.speed.toStringAsFixed(1),
          style: const TextStyle(color: Colors.white70, fontSize: 12)),
      btn(Icons.add, () => c.setSpeed(s.speed + 0.25)),
      btn(Icons.text_decrease,
          () => s.fontSize = (s.fontSize - 2).clamp(14, 72)),
      btn(Icons.text_increase,
          () => s.fontSize = (s.fontSize + 2).clamp(14, 72)),
      btn(Icons.close, _close),
      const SizedBox(width: 4),
    ]);
  }
}
