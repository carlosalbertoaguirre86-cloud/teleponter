// Cámara detrás del guion (Android): vista previa y grabación de vídeo.
// El texto del teleprompter NO se graba en el vídeo: es sólo interfaz.

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:gal/gal.dart';

class CameraLayerController extends ChangeNotifier {
  CameraController? camera;
  List<CameraDescription> _cameras = const [];
  int _index = 0;
  bool recording = false;
  bool busy = false;
  String? error;
  String? message;

  bool get ready => camera?.value.isInitialized ?? false;
  bool get canSwitch => _cameras.length > 1 && !recording;

  Future<void> init() async {
    try {
      _cameras = await availableCameras();
      if (_cameras.isEmpty) {
        error = 'No se encontró ninguna cámara.';
        notifyListeners();
        return;
      }
      final front = _cameras
          .indexWhere((c) => c.lensDirection == CameraLensDirection.front);
      _index = front >= 0 ? front : 0;
      await _open();
    } catch (e) {
      error = 'No se pudo abrir la cámara: $e';
      notifyListeners();
    }
  }

  Future<void> _open() async {
    final old = camera;
    camera = null;
    notifyListeners();
    await old?.dispose();
    final ctrl = CameraController(
      _cameras[_index],
      ResolutionPreset.high,
      enableAudio: true,
    );
    await ctrl.initialize();
    camera = ctrl;
    error = null;
    notifyListeners();
  }

  Future<void> switchCamera() async {
    if (!canSwitch) return;
    _index = (_index + 1) % _cameras.length;
    try {
      await _open();
    } catch (e) {
      error = 'No se pudo cambiar de cámara: $e';
      notifyListeners();
    }
  }

  Future<void> toggleRecording() async {
    final ctrl = camera;
    if (ctrl == null || !ready || busy) return;
    busy = true;
    notifyListeners();
    try {
      if (!recording) {
        await ctrl.startVideoRecording();
        recording = true;
      } else {
        final file = await ctrl.stopVideoRecording();
        recording = false;
        try {
          if (!await Gal.hasAccess(toAlbum: true)) {
            await Gal.requestAccess(toAlbum: true);
          }
          await Gal.putVideo(file.path, album: 'Teleponter');
          message = 'Vídeo guardado en la galería (álbum Teleponter).';
        } catch (e) {
          message = 'No se pudo guardar en la galería. Archivo: ${file.path}';
        }
      }
    } catch (e) {
      error = 'Error de grabación: $e';
      recording = false;
    }
    busy = false;
    notifyListeners();
  }

  @override
  void dispose() {
    final ctrl = camera;
    camera = null;
    if (recording) {
      ctrl?.stopVideoRecording().ignore();
    }
    ctrl?.dispose();
    super.dispose();
  }
}

class CameraPreviewLayer extends StatelessWidget {
  const CameraPreviewLayer({super.key, required this.controller});
  final CameraLayerController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final cam = controller.camera;
        if (controller.error != null) {
          return Center(
            child: Text(controller.error!,
                style: const TextStyle(color: Colors.white54)),
          );
        }
        if (cam == null || !controller.ready) {
          return const Center(child: CircularProgressIndicator());
        }
        return LayoutBuilder(builder: (context, box) {
          // Rellenar la pantalla manteniendo la proporción (como "cover").
          final ratio = cam.value.aspectRatio;
          final portrait = box.maxHeight > box.maxWidth;
          final previewRatio = portrait ? 1 / ratio : ratio;
          return ClipRect(
            child: SizedBox.expand(
              child: FittedBox(
                fit: BoxFit.cover,
                child: SizedBox(
                  width: box.maxWidth,
                  height: box.maxWidth / previewRatio,
                  child: CameraPreview(cam),
                ),
              ),
            ),
          );
        });
      },
    );
  }
}
