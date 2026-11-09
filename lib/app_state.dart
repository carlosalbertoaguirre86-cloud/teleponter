import 'package:flutter/widgets.dart';

import 'core/settings.dart';
import 'services/prompter_controller.dart';
import 'services/remote_server.dart';

/// Contenedor de los objetos globales de la app.
class AppState extends ChangeNotifier {
  AppState(this.settings) : prompter = PrompterController(settings) {
    remote = RemoteServer(prompter);
    director = DirectorServer(prompter);
    final saved = settings.savedPages;
    prompter.pages = saved.isEmpty ? [''] : List.of(saved);
    settings.addListener(_syncServers);
    _syncServers();
  }

  final AppSettings settings;
  final PrompterController prompter;
  late final RemoteServer remote;
  late final DirectorServer director;

  bool _remoteWanted = false;
  int _remotePort = 0;
  bool _directorWanted = false;
  int _directorPort = 0;

  Future<void> _syncServers() async {
    final rw = settings.remoteEnabled, rp = settings.remotePort;
    if (rw != _remoteWanted || rp != _remotePort) {
      _remoteWanted = rw;
      _remotePort = rp;
      if (rw) {
        await remote.start(rp);
      } else {
        await remote.stop();
      }
      notifyListeners();
    }
    final dw = settings.directorEnabled, dp = settings.directorPort;
    if (dw != _directorWanted || dp != _directorPort) {
      _directorWanted = dw;
      _directorPort = dp;
      if (dw) {
        await director.start(dp);
      } else {
        await director.stop();
      }
      notifyListeners();
    }
  }

  void savePages() => settings.savedPages = prompter.pages;
}

class AppScope extends InheritedWidget {
  const AppScope({super.key, required this.state, required super.child});
  final AppState state;

  static AppState of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppScope>()!.state;

  @override
  bool updateShouldNotify(AppScope old) => old.state != state;
}
