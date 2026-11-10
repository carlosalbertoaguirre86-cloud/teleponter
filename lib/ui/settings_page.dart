import 'dart:io';

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:screen_retriever/screen_retriever.dart';
import 'package:speech_to_text/speech_to_text.dart';

import '../app_state.dart';
import '../core/version.dart';
import '../core/settings.dart';
import '../services/window_service.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  List<LocaleName> _locales = const [];
  List<Display> _displays = const [];
  bool _loadingLocales = false;

  @override
  void initState() {
    super.initState();
    if (isDesktop) {
      WindowService.instance.displays().then((d) {
        if (mounted) setState(() => _displays = d);
      });
    }
  }

  Future<void> _loadLocales() async {
    setState(() => _loadingLocales = true);
    final stt = SpeechToText();
    try {
      if (await stt.initialize()) {
        final list = await stt.locales();
        list.sort((a, b) => a.name.compareTo(b.name));
        _locales = list;
      }
    } catch (_) {}
    if (mounted) setState(() => _loadingLocales = false);
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final s = app.settings;
    return ListenableBuilder(
      listenable: Listenable.merge([s, app]),
      builder: (context, _) => Scaffold(
        appBar: AppBar(title: const Text('Ajustes')),
        body: ListView(
          padding: const EdgeInsets.only(bottom: 40),
          children: [
            _header('Guía'),
            RadioGroup<GuidanceMode>(
              groupValue: s.guidance,
              onChanged: (v) => s.guidance = v!,
              child: Column(children: [
                for (final m in GuidanceMode.values)
                  RadioListTile<GuidanceMode>(
                    value: m,
                    title: Text(guidanceLabels[m]!),
                    subtitle: Text(switch (m) {
                      GuidanceMode.wordTracking =>
                        'Resalta cada palabra mientras la dices (usa el reconocimiento de voz del sistema).',
                      GuidanceMode.classic =>
                        'Desplaza a velocidad constante. No usa micrófono.',
                      GuidanceMode.voiceActivated =>
                        'Avanza mientras hablas y se detiene cuando callas.',
                    }),
                  ),
              ]),
            ),
            _slider('Velocidad (palabras/seg)', s.speed, 0.5, 8, 15,
                (v) => s.speed = v,
                label: s.speed.toStringAsFixed(1)),
            ListTile(
              title: const Text('Idioma del reconocimiento de voz'),
              subtitle: Text(s.speechLocale.isEmpty
                  ? 'Idioma del sistema'
                  : _locales
                          .where((l) => l.localeId == s.speechLocale)
                          .map((l) => l.name)
                          .firstOrNull ??
                      s.speechLocale),
              trailing: _loadingLocales
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.language),
              onTap: () async {
                if (_locales.isEmpty) await _loadLocales();
                if (!context.mounted) return;
                final picked = await showDialog<String>(
                  context: context,
                  builder: (ctx) => SimpleDialog(
                    title: const Text('Idioma'),
                    children: [
                      SimpleDialogOption(
                        onPressed: () => Navigator.pop(ctx, ''),
                        child: const Text('Idioma del sistema'),
                      ),
                      if (_locales.isEmpty)
                        const Padding(
                          padding: EdgeInsets.all(16),
                          child: Text(
                              'No se pudieron obtener los idiomas. Revisa el permiso de micrófono.'),
                        ),
                      for (final l in _locales)
                        SimpleDialogOption(
                          onPressed: () => Navigator.pop(ctx, l.localeId),
                          child: Text('${l.name}  (${l.localeId})'),
                        ),
                    ],
                  ),
                );
                if (picked != null) s.speechLocale = picked;
              },
            ),
            SwitchListTile(
              title: const Text('Pasar de página automáticamente'),
              subtitle:
                  const Text('Cuenta atrás de 3 s al terminar una página.'),
              value: s.autoAdvancePages,
              onChanged: (v) => s.autoAdvancePages = v,
            ),
            if (isDesktop) ...[
              _header('Ventana (Windows)'),
              RadioGroup<OverlayMode>(
                groupValue: s.overlay,
                onChanged: (v) => s.overlay = v!,
                child: Column(children: [
                  for (final m in OverlayMode.values)
                    RadioListTile<OverlayMode>(
                      value: m,
                      title: Text(overlayLabels[m]!),
                      subtitle: Text(switch (m) {
                        OverlayMode.pinnedTop =>
                          'Franja pegada al borde superior, cerca de la cámara web. Siempre encima.',
                        OverlayMode.floating =>
                          'Ventana pequeña que puedes arrastrar a cualquier lugar. Siempre encima.',
                        OverlayMode.fullscreen =>
                          'Ocupa toda la pantalla elegida. Esc para salir.',
                      }),
                    ),
                ]),
              ),
              _slider('Ancho de la ventana', s.overlayWidth, 280, 1000, 72,
                  (v) => s.overlayWidth = v,
                  label: '${s.overlayWidth.round()} px'),
              _slider('Alto del texto', s.overlayHeight, 100, 600, 50,
                  (v) => s.overlayHeight = v,
                  label: '${s.overlayHeight.round()} px'),
              _slider('Opacidad de la ventana', s.glassOpacity, 0.4, 1, 12,
                  (v) => s.glassOpacity = v,
                  label: '${(s.glassOpacity * 100).round()} %'),
              if (_displays.length > 1)
                ListTile(
                  title: const Text('Pantalla para modo completo'),
                  trailing: DropdownButton<int>(
                    value: s.displayIndex.clamp(0, _displays.length - 1),
                    items: [
                      for (var i = 0; i < _displays.length; i++)
                        DropdownMenuItem(
                          value: i,
                          child: Text(_displays[i].name ?? 'Pantalla ${i + 1}'),
                        ),
                    ],
                    onChanged: (v) => s.displayIndex = v ?? 0,
                  ),
                ),
              if (Platform.isWindows)
                SwitchListTile(
                  title: const Text('Ocultar al compartir pantalla'),
                  subtitle: const Text(
                      'El teleprompter no aparece en grabaciones ni en videollamadas (Windows 10 2004 o posterior).'),
                  value: s.hideFromCapture,
                  onChanged: (v) => s.hideFromCapture = v,
                ),
            ],
            if (Platform.isAndroid) ...[
              _header('Móvil (Android)'),
              SwitchListTile(
                title: const Text('Franja junto a la cámara frontal'),
                subtitle: const Text(
                    'El texto ocupa una franja estrecha arriba, pegada al lente, para que no se note que lees. La ventana flotante usa el mismo tamaño.'),
                value: s.phoneBand,
                onChanged: (v) => s.phoneBand = v,
              ),
              if (s.phoneBand) ...[
                _slider('Líneas visibles en la franja', s.bandLines, 1, 8, 7,
                    (v) => s.bandLines = v,
                    label: s.bandLines.round().toString()),
                _slider('Ancho de la franja', s.bandWidth, 0.4, 1, 12,
                    (v) => s.bandWidth = v,
                    label: '${(s.bandWidth * 100).round()} %'),
              ],
              _slider('Tamaño de la ventana flotante', s.floatScale, 0.5, 2.5,
                  20, (v) => s.floatScale = v,
                  label: '${(s.floatScale * 100).round()} %'),
            ],
            _header('Texto'),
            ListTile(
              title: const Text('Tipo de letra'),
              trailing: DropdownButton<PromptFont>(
                value: s.font,
                items: [
                  for (final f in PromptFont.values)
                    DropdownMenuItem(value: f, child: Text(fontLabels[f]!)),
                ],
                onChanged: (v) => s.font = v!,
              ),
            ),
            _slider('Tamaño de letra', s.fontSize, 14, 96, 41,
                (v) => s.fontSize = v,
                label: '${s.fontSize.round()} pt'),
            ListTile(
              title: const Text('Color de resaltado'),
              subtitle: Wrap(spacing: 8, children: [
                for (final e in highlightColors.entries)
                  ChoiceChip(
                    label: Text(e.key),
                    avatar: CircleAvatar(backgroundColor: e.value, radius: 7),
                    selected: s.highlightName == e.key,
                    onSelected: (_) => s.highlightName = e.key,
                  ),
              ]),
            ),
            ListTile(
              title: const Text('Espejo (cristal de teleprompter)'),
              trailing: DropdownButton<MirrorMode>(
                value: s.mirror,
                items: [
                  for (final m in MirrorMode.values)
                    DropdownMenuItem(value: m, child: Text(mirrorLabels[m]!)),
                ],
                onChanged: (v) => s.mirror = v!,
              ),
            ),
            SwitchListTile(
              title: const Text('Línea de lectura arriba'),
              subtitle: const Text(
                  'Cerca de la cámara para mantener contacto visual. Desactívalo para centrarla.'),
              value: s.readingLineTop,
              onChanged: (v) => s.readingLineTop = v,
            ),
            _header('Conexión remota'),
            SwitchListTile(
              title: const Text('Ver el teleprompter en otro dispositivo'),
              subtitle: const Text(
                  'Abre un servidor en tu red local. Cualquier navegador de la misma Wi-Fi puede verlo.'),
              value: s.remoteEnabled,
              onChanged: (v) => s.remoteEnabled = v,
            ),
            if (s.remoteEnabled)
              _serverInfo(
                  app.remote.running, app.remote.url, app.remote.lastError),
            _portField('Puerto remoto', s.remotePort, (v) => s.remotePort = v),
            _header('Modo director'),
            SwitchListTile(
              title: const Text('Permitir que un director controle el guion'),
              subtitle: const Text(
                  'Otra persona escribe y envía el texto en directo desde su navegador.'),
              value: s.directorEnabled,
              onChanged: (v) => s.directorEnabled = v,
            ),
            if (s.directorEnabled)
              _serverInfo(app.director.running, app.director.url,
                  app.director.lastError),
            _portField(
                'Puerto director', s.directorPort, (v) => s.directorPort = v),
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 24, 16, 0),
              child: Text(
                'Teleponter versión $appVersion. '
                'Teleponter está basado en Textream de Fatih Kadir Akin (licencia MIT). '
                'Úsalo sólo en redes de confianza: la conexión remota no está cifrada.',
                style: TextStyle(fontSize: 12, color: Colors.white54),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _header(String text) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 24, 16, 4),
        child: Text(text,
            style: TextStyle(
                color: Theme.of(context).colorScheme.primary,
                fontWeight: FontWeight.w600)),
      );

  Widget _slider(String title, double value, double min, double max,
      int divisions, ValueChanged<double> onChanged,
      {required String label}) {
    return ListTile(
      title: Text(title),
      subtitle: Slider(
        value: value.clamp(min, max),
        min: min,
        max: max,
        divisions: divisions,
        label: label,
        onChanged: onChanged,
      ),
      trailing: Text(label),
    );
  }

  Widget _serverInfo(bool running, String url, String? error) {
    if (!running) {
      return ListTile(
        leading: const Icon(Icons.error_outline, color: Colors.redAccent),
        title: Text(error ?? 'Iniciando…'),
      );
    }
    return ListTile(
      leading: Container(
        color: Colors.white,
        padding: const EdgeInsets.all(4),
        child: QrImageView(data: url, size: 72, padding: EdgeInsets.zero),
      ),
      title: SelectableText(url),
      subtitle: const Text('Escanéalo con el móvil (misma red Wi-Fi).'),
    );
  }

  Widget _portField(String label, int value, ValueChanged<int> onChanged) {
    return ListTile(
      title: Text(label),
      trailing: SizedBox(
        width: 100,
        child: TextFormField(
          initialValue: '$value',
          keyboardType: TextInputType.number,
          textAlign: TextAlign.end,
          onFieldSubmitted: (t) {
            final v = int.tryParse(t);
            if (v != null && v > 1024 && v < 65536) onChanged(v);
          },
        ),
      ),
    );
  }
}
