// Pantalla principal: editor de guion por páginas, archivos y arranque.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../app_state.dart';
import '../core/pptx_notes.dart';
import '../core/settings.dart';
import '../services/floating_service.dart';
import '../services/prompter_controller.dart';
import '../services/window_service.dart';
import 'prompter_screen.dart';
import 'settings_page.dart';

const _sampleScript =
    'Bienvenido a Teleponter. Pega aquí tu guion, pulsa Iniciar y empieza a '
    'hablar. [sonríe] Las palabras se resaltan a medida que las lees. '
    'El texto entre corchetes es una nota para ti y no hace falta leerlo. '
    'Cuando termines, el teleprompter se cierra solo.';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _text = TextEditingController();
  String? _filePath; // ruta en disco (Windows) para "Guardar"
  String _fileName = 'Sin título';
  List<String> _savedSnapshot = [''];
  bool _loadedOnce = false;
  bool _prompterOpen = false;
  bool _pendingRecord = false;
  PrompterController? _listened;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_loadedOnce) return;
    _loadedOnce = true;
    final p = AppScope.of(context).prompter;
    if (p.pages.every((t) => t.trim().isEmpty)) p.pages = [_sampleScript];
    p.pageIndex = 0;
    _text.text = p.pages[0];
    _savedSnapshot = List.of(p.pages);
    p.addListener(_onPrompterChange);
    _listened = p;
  }

  /// Abre la pantalla de lectura si el teleprompter arranca desde fuera
  /// (por ejemplo, el modo director).
  void _onPrompterChange() {
    final p = _listened;
    if (p != null && p.active && !_prompterOpen && mounted) {
      _openPrompter(record: _pendingRecord);
    }
  }

  @override
  void dispose() {
    _listened?.removeListener(_onPrompterChange);
    _text.dispose();
    super.dispose();
  }

  AppState get app => AppScope.of(context);

  void _onEdit(String value) {
    final p = app.prompter;
    p.pages[p.pageIndex] = value;
    app.savePages();
    setState(() {});
  }

  void _selectPage(int i) {
    final p = app.prompter;
    setState(() {
      p.pageIndex = i;
      _text.text = p.pages[i];
    });
  }

  void _addPage() {
    final p = app.prompter;
    p.pages.add('');
    _selectPage(p.pages.length - 1);
    app.savePages();
  }

  void _deletePage(int i) {
    final p = app.prompter;
    if (p.pages.length <= 1) {
      p.pages[0] = '';
      _selectPage(0);
    } else {
      p.pages.removeAt(i);
      _selectPage((i - 1).clamp(0, p.pages.length - 1));
    }
    app.savePages();
  }

  bool get _dirty {
    final pages = app.prompter.pages;
    if (pages.length != _savedSnapshot.length) return true;
    for (var i = 0; i < pages.length; i++) {
      if (pages[i] != _savedSnapshot[i]) return true;
    }
    return false;
  }

  void _setPages(List<String> pages, {String? name, String? path}) {
    final p = app.prompter;
    p.pages = pages.isEmpty ? [''] : pages;
    _filePath = path;
    _fileName = name ?? 'Sin título';
    _savedSnapshot = List.of(p.pages);
    app.savePages();
    _selectPage(0);
  }

  // ---------------------------------------------------------------------
  // Archivos

  Future<bool> _confirmDiscard() async {
    if (!_dirty) return true;
    final r = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Descartar cambios?'),
        content: const Text('El guion actual tiene cambios sin guardar.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Descartar')),
        ],
      ),
    );
    return r ?? false;
  }

  Future<void> _newScript() async {
    if (!await _confirmDiscard()) return;
    _setPages(['']);
  }

  Future<void> _open() async {
    if (!await _confirmDiscard()) return;
    final file = await FilePicker.pickFile(
      dialogTitle: 'Abrir guion (.textream, .pptx o .txt)',
    );
    if (file == null) return;
    try {
      final bytes = await file.readAsBytes();
      final name = file.name;
      final ext = name.split('.').last.toLowerCase();
      if (ext == 'pptx') {
        final pages = extractPptxNotes(bytes);
        _setPages(pages,
            name:
                name.replaceAll(RegExp(r'\.pptx$', caseSensitive: false), ''));
        _snack('Importadas ${pages.length} páginas de notas del presentador.');
      } else if (ext == 'textream') {
        final decoded = jsonDecode(utf8.decode(bytes));
        final pages = (decoded as List).map((e) => e.toString()).toList();
        _setPages(pages, name: name, path: file.path);
      } else if (ext == 'key') {
        _snack('Keynote no se puede importar: expórtalo primero a PowerPoint.');
      } else {
        final text = utf8.decode(bytes, allowMalformed: true);
        _setPages([text], name: name);
      }
    } catch (e) {
      _snack('No se pudo abrir el archivo: $e');
    }
  }

  Future<void> _save({bool saveAs = false}) async {
    final bytes =
        Uint8List.fromList(utf8.encode(jsonEncode(app.prompter.pages)));
    try {
      if (!saveAs && _filePath != null && Platform.isWindows) {
        await File(_filePath!).writeAsBytes(bytes, flush: true);
      } else {
        var name = _fileName == 'Sin título' ? 'Guion' : _fileName;
        if (!name.toLowerCase().endsWith('.textream')) name = '$name.textream';
        final uri = await FilePicker.saveFile(
          dialogTitle: 'Guardar guion',
          fileName: name,
          bytes: bytes,
          mimeType: 'application/json',
        );
        if (uri == null) return;
        if (uri.scheme == 'file') {
          _filePath = uri.toFilePath();
          // En Windows el diálogo puede no escribir el archivo por sí mismo.
          if (Platform.isWindows) {
            await File(_filePath!).writeAsBytes(bytes, flush: true);
          }
        }
        _fileName = Uri.decodeComponent(
            uri.pathSegments.isEmpty ? name : uri.pathSegments.last);
      }
      setState(() => _savedSnapshot = List.of(app.prompter.pages));
      _snack('Guion guardado.');
    } catch (e) {
      _snack('No se pudo guardar: $e');
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  // ---------------------------------------------------------------------
  // Teleprompter

  Future<void> _start({bool record = false, bool fromFirst = false}) async {
    final p = app.prompter;
    if (p.pages.every((t) => t.trim().isEmpty)) {
      _snack('Escribe o pega un guion primero.');
      return;
    }
    _pendingRecord = record;
    await p.start(fromPage: fromFirst ? 0 : p.pageIndex);
  }

  Future<void> _openPrompter({bool record = false}) async {
    _prompterOpen = true;
    _pendingRecord = false;
    final p = app.prompter;
    await WindowService.instance.enterPrompter(app.settings);
    if (!mounted) return;
    await Navigator.of(context).push(PageRouteBuilder(
      opaque: true,
      pageBuilder: (_, __, ___) =>
          PrompterScreen(controller: p, recordMode: record),
      transitionDuration: const Duration(milliseconds: 180),
      transitionsBuilder: (_, a, __, child) =>
          FadeTransition(opacity: a, child: child),
    ));
    if (p.active) await p.stop();
    await WindowService.instance.exitPrompter();
    _prompterOpen = false;
    if (mounted) {
      final idx = p.pageIndex.clamp(0, p.pages.length - 1);
      _selectPage(idx);
    }
  }

  /// Android: abre el teleprompter en una ventana flotante encima de
  /// cualquier app (cámara, Instagram, TikTok, Zoom...).
  Future<void> _startFloating() async {
    final p = app.prompter;
    final screenWidth = MediaQuery.sizeOf(context).width;
    if (p.pages.every((t) => t.trim().isEmpty)) {
      _snack('Escribe o pega un guion primero.');
      return;
    }
    // Si ya está abierta, el mismo botón la cierra.
    if (await FloatingService.isActive()) {
      await FloatingService.close();
      _snack('Ventana flotante cerrada.');
      return;
    }
    if (!await FloatingService.hasPermission()) {
      if (!mounted) return;
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Permiso necesario'),
          content: const Text(
              'Para que el teleprompter flote encima de otras apps, Android pide '
              'activar "Mostrar sobre otras apps" para Teleponter.\n\n'
              'Se abrirá la pantalla de ajustes: activa el interruptor y vuelve.'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancelar')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Abrir ajustes')),
          ],
        ),
      );
      if (ok != true) return;
      if (!await FloatingService.requestPermission()) {
        _snack('Sin el permiso no se puede mostrar la ventana flotante.');
        return;
      }
    }
    await FloatingService.show(
      settings: app.settings,
      pages: List.of(p.pages),
      pageIndex: p.pageIndex,
      screenWidth: screenWidth,
    );
    _snack('Ventana flotante activa. Abre la app con la que vas a grabar y '
        'pulsa ▶ en la ventana. En modo flotante el texto avanza a velocidad fija.');
  }

  void _showQr(String title, String url, String help) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: SizedBox(
          width: 280,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              color: Colors.white,
              padding: const EdgeInsets.all(10),
              child: QrImageView(data: url, size: 220),
            ),
            const SizedBox(height: 12),
            SelectableText(url, textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text(help,
                style: const TextStyle(fontSize: 12, color: Colors.white60)),
          ]),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cerrar')),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    return ListenableBuilder(
      listenable: Listenable.merge([app, app.settings]),
      builder: (context, _) {
        final s = app.settings;
        final p = app.prompter;
        final narrow = MediaQuery.sizeOf(context).width < 600;
        return Scaffold(
          appBar: AppBar(
            title: Text('Teleponter — $_fileName${_dirty ? ' •' : ''}',
                overflow: TextOverflow.ellipsis),
            actions: [
              if (s.remoteEnabled && app.remote.running)
                IconButton(
                  icon: const Icon(Icons.qr_code),
                  tooltip: 'Conexión remota',
                  onPressed: () => _showQr(
                    'Ver en otro dispositivo',
                    app.remote.url,
                    'Escanea con el móvil o la tablet (misma red Wi-Fi).',
                  ),
                ),
              IconButton(
                  icon: const Icon(Icons.note_add_outlined),
                  tooltip: 'Nuevo',
                  onPressed: _newScript),
              IconButton(
                  icon: const Icon(Icons.folder_open),
                  tooltip: 'Abrir / importar PowerPoint',
                  onPressed: _open),
              IconButton(
                  icon: const Icon(Icons.save_outlined),
                  tooltip: 'Guardar',
                  onPressed: () => _save()),
              if (!narrow)
                IconButton(
                    icon: const Icon(Icons.save_as_outlined),
                    tooltip: 'Guardar como…',
                    onPressed: () => _save(saveAs: true)),
              IconButton(
                icon: const Icon(Icons.settings),
                tooltip: 'Ajustes',
                onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const SettingsPage())),
              ),
            ],
          ),
          body: Stack(children: [
            Column(children: [
              _pageTabs(p.pages, p.pageIndex),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
                  child: TextField(
                    controller: _text,
                    onChanged: _onEdit,
                    maxLines: null,
                    expands: true,
                    textAlignVertical: TextAlignVertical.top,
                    style: const TextStyle(fontSize: 18, height: 1.5),
                    decoration: InputDecoration(
                      hintText:
                          'Escribe o pega tu guion. Usa [corchetes] para notas que no se leen.',
                      filled: true,
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
              ),
              _bottomBar(s, narrow),
            ]),
            if (s.directorEnabled && app.director.running)
              _directorOverlay(app),
          ]),
        );
      },
    );
  }

  Widget _pageTabs(List<String> pages, int current) {
    return SizedBox(
      height: 48,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        children: [
          for (var i = 0; i < pages.length; i++)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: InputChip(
                label: Text('Página ${i + 1}'),
                selected: i == current,
                onPressed: () => _selectPage(i),
                onDeleted: pages.length > 1 ? () => _deletePage(i) : null,
                deleteButtonTooltipMessage: 'Eliminar página',
              ),
            ),
          ActionChip(
            avatar: const Icon(Icons.add, size: 18),
            label: const Text('Página'),
            onPressed: _addPage,
          ),
        ],
      ),
    );
  }

  Widget _bottomBar(AppSettings s, bool narrow) {
    final multi =
        app.prompter.pages.where((t) => t.trim().isNotEmpty).length > 1;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        child: Wrap(
          spacing: 10,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          alignment: WrapAlignment.spaceBetween,
          children: [
            SegmentedButton<GuidanceMode>(
              segments: [
                ButtonSegment(
                    value: GuidanceMode.wordTracking,
                    icon: const Icon(Icons.record_voice_over),
                    label: Text(narrow ? 'Voz' : 'Seguir palabras')),
                ButtonSegment(
                    value: GuidanceMode.classic,
                    icon: const Icon(Icons.speed),
                    label: Text(narrow ? 'Clásico' : 'Clásico')),
                ButtonSegment(
                    value: GuidanceMode.voiceActivated,
                    icon: const Icon(Icons.graphic_eq),
                    label: Text(narrow ? 'Pausa' : 'Activado por voz')),
              ],
              selected: {s.guidance},
              onSelectionChanged: (v) => s.guidance = v.first,
              showSelectedIcon: false,
            ),
            Row(mainAxisSize: MainAxisSize.min, children: [
              if (multi)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: OutlinedButton.icon(
                    onPressed: () => _start(fromFirst: true),
                    icon: const Icon(Icons.replay),
                    label: const Text('Desde pág. 1'),
                  ),
                ),
              if (Platform.isAndroid)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: FilledButton.tonalIcon(
                    onPressed: _startFloating,
                    icon: const Icon(Icons.picture_in_picture_alt),
                    label: const Text('Flotante'),
                  ),
                ),
              if (Platform.isAndroid)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: FilledButton.tonalIcon(
                    onPressed: () => _start(record: true),
                    icon: const Icon(Icons.videocam),
                    label: const Text('Grabar'),
                  ),
                ),
              FilledButton.icon(
                onPressed: () => _start(),
                icon: const Icon(Icons.play_arrow),
                label: const Text('Iniciar'),
                style: FilledButton.styleFrom(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
                ),
              ),
            ]),
          ],
        ),
      ),
    );
  }

  Widget _directorOverlay(AppState app) {
    return Positioned.fill(
      child: Container(
        color: Colors.black.withValues(alpha: 0.92),
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Text('Modo director activo',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              const Text(
                'El director escribe y envía el guion desde su navegador.\n'
                'Escanea el código o abre el enlace en la misma red Wi-Fi.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white70),
              ),
              const SizedBox(height: 16),
              Container(
                color: Colors.white,
                padding: const EdgeInsets.all(10),
                child: QrImageView(data: app.director.url, size: 200),
              ),
              const SizedBox(height: 10),
              SelectableText(app.director.url),
              const SizedBox(height: 16),
              OutlinedButton(
                onPressed: () => app.settings.directorEnabled = false,
                child: const Text('Desactivar modo director'),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
