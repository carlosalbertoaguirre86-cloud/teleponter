// Servidor HTTP + WebSocket local para ver el teleprompter desde cualquier
// navegador (móvil, tablet u otro PC) y para el modo director.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../core/settings.dart';
import 'net_utils.dart';
import 'web_pages.dart';
import 'prompter_controller.dart';

Map<String, Object?> prompterState(PrompterController c) {
  final color = c.settings.highlightColor;
  String hex(int v) => v.toRadixString(16).padLeft(2, '0');
  final argb = color.toARGB32();
  return {
    'words': c.words,
    'annotation': c.annotation,
    'highlightedCharCount': c.highlightedCharCount,
    'totalCharCount': c.collapsed.length,
    'wordPosition': c.wordPosition,
    'audioLevels': c.levels,
    'isListening': c.isListening,
    'isSpeaking': c.isSpeaking,
    'isActive': c.active,
    'isDone': c.done,
    'isPaused': c.paused,
    'isMuted': c.muted,
    'countdown': c.countdown,
    'hasNextPage': c.hasNextPage,
    'page': c.pageIndex + 1,
    'pageCount': c.pages.length,
    'mode': c.mode.name,
    'cueColor':
        '#${hex((argb >> 16) & 0xff)}${hex((argb >> 8) & 0xff)}${hex(argb & 0xff)}',
    'lastSpokenText': c.lastSpokenText,
  };
}

/// Base común: HTTP para la página + WebSocket para el estado.
abstract class _LocalServer {
  _LocalServer(this.controller);
  final PrompterController controller;
  HttpServer? _server;
  final Set<WebSocket> _sockets = {};
  Timer? _broadcast;
  String url = '';
  String? lastError;

  bool get running => _server != null;
  int get clientCount => _sockets.length;

  String get pageHtml;
  bool authorize(HttpRequest req) => true;
  void onMessage(WebSocket ws, Map<String, dynamic> msg) {}
  Map<String, Object?> extraState() => const {};

  Future<bool> start(int port) async {
    await stop();
    try {
      final server = await HttpServer.bind(InternetAddress.anyIPv4, port);
      _server = server;
      final ip = await localIpAddress();
      url = 'http://$ip:$port/${urlSuffix()}';
      lastError = null;
      server.listen(_handle, onError: (_) {});
      _broadcast = Timer.periodic(
          const Duration(milliseconds: 100), (_) => _sendState());
      return true;
    } catch (e) {
      lastError = 'No se pudo abrir el puerto $port: $e';
      return false;
    }
  }

  String urlSuffix() => '';

  Future<void> stop() async {
    _broadcast?.cancel();
    _broadcast = null;
    for (final ws in _sockets.toList()) {
      await ws.close();
    }
    _sockets.clear();
    await _server?.close(force: true);
    _server = null;
  }

  Future<void> _handle(HttpRequest req) async {
    try {
      if (req.uri.path == '/ws' && WebSocketTransformer.isUpgradeRequest(req)) {
        if (!authorize(req)) {
          req.response.statusCode = HttpStatus.forbidden;
          await req.response.close();
          return;
        }
        final ws = await WebSocketTransformer.upgrade(req);
        _sockets.add(ws);
        ws.listen(
          (data) {
            if (data is! String) return;
            try {
              final msg = jsonDecode(data);
              if (msg is Map<String, dynamic>) onMessage(ws, msg);
            } catch (_) {}
          },
          onDone: () => _sockets.remove(ws),
          onError: (_) => _sockets.remove(ws),
          cancelOnError: true,
        );
        _sendState();
        return;
      }
      if (req.uri.path == '/' || req.uri.path == '/index.html') {
        req.response.headers.contentType = ContentType.html;
        req.response.headers.set('Cache-Control', 'no-store');
        req.response.write(pageHtml);
        await req.response.close();
        return;
      }
      req.response.statusCode = HttpStatus.notFound;
      await req.response.close();
    } catch (_) {
      try {
        await req.response.close();
      } catch (_) {}
    }
  }

  void _sendState() {
    if (_sockets.isEmpty) return;
    final payload = jsonEncode({...prompterState(controller), ...extraState()});
    for (final ws in _sockets.toList()) {
      try {
        ws.add(payload);
      } catch (_) {
        _sockets.remove(ws);
      }
    }
  }
}

class RemoteServer extends _LocalServer {
  RemoteServer(super.controller);

  @override
  String get pageHtml => remoteViewerHtml;
}

class DirectorServer extends _LocalServer {
  DirectorServer(super.controller);
  final String token = randomToken();

  @override
  String urlSuffix() => '?t=$token';

  @override
  String get pageHtml => directorHtml;

  @override
  bool authorize(HttpRequest req) => req.uri.queryParameters['t'] == token;

  @override
  Map<String, Object?> extraState() => {
        'text': controller.pages.isEmpty
            ? ''
            : controller.pages[
                controller.pageIndex.clamp(0, controller.pages.length - 1)]
      };

  @override
  void onMessage(WebSocket ws, Map<String, dynamic> msg) {
    final type = msg['type'];
    final text = (msg['text'] as String?) ?? '';
    switch (type) {
      case 'setText':
        if (text.trim().isNotEmpty) {
          controller.settings.guidance = GuidanceMode.wordTracking;
          controller.directorSetText(text);
        }
      case 'updateText':
        final read = (msg['readCharCount'] as num?)?.toInt() ??
            controller.highlightedCharCount;
        controller.directorUpdateText(text, read);
      case 'stop':
        controller.onFinished?.call();
      case 'pause':
        controller.togglePause();
    }
  }
}
