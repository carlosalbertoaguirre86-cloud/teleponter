# Teleponter

Teleprompter libre para **Windows** y **Android**, hecho con Flutter.
Es un port de [Textream](https://github.com/f/textream) (macOS/iOS, licencia MIT) de Fatih Kadir Akin.

## Funciones

| Función | Windows | Android |
|---|:---:|:---:|
| Editor de guion con varias páginas | ✅ | ✅ |
| **Seguimiento de palabras**: resalta lo que vas diciendo | ✅ (*) | ✅ |
| **Clásico**: desplazamiento a velocidad fija (0,5–8 palabras/s) | ✅ | ✅ |
| **Activado por voz**: avanza mientras hablas y se detiene cuando callas | ✅ | ✅ |
| Notas entre `[corchetes]`: se muestran pero no hace falta leerlas | ✅ | ✅ |
| Tocar una palabra para saltar a ella; rueda o arrastre para ajustar | ✅ | ✅ |
| Isla superior (cerca de la webcam), ventana flotante o pantalla completa, siempre encima | ✅ | — |
| Ocultar el teleprompter de grabaciones y videollamadas | ✅ | — |
| Modo espejo (horizontal, vertical o ambos) para cristal de teleprompter | ✅ | ✅ |
| Fuentes Sans, Serif, Mono y OpenDyslexic; tamaño y color de resaltado | ✅ | ✅ |
| **Conexión remota**: ver el guion en cualquier navegador mediante un código QR | ✅ | ✅ |
| **Modo director**: otra persona escribe el guion en directo desde su navegador | ✅ | ✅ |
| Importar notas del presentador de PowerPoint (.pptx) | ✅ | ✅ |
| Abrir y guardar archivos `.textream` (compatibles con la app de Mac) | ✅ | ✅ |
| Cámara detrás del guion y **grabación de vídeo** (el texto no sale en el vídeo) | — | ✅ |

(*) En Windows el reconocimiento de voz usa el motor de Windows a través del plugin `speech_to_text`, cuyo soporte para Windows aún es reciente. Si no te funciona bien, usa el modo **Activado por voz**, que solo mide el volumen del micrófono.

### Atajos de teclado (mientras lees)

`Espacio` pausa · `Esc` cerrar · `↑/↓` velocidad · `←/→` página anterior/siguiente · `M` silenciar micrófono

---

## Opción 1: compilar con GitHub (sin instalar nada)

Solo necesitas una cuenta gratuita de GitHub.

1. Entra en <https://github.com/new>, ponle un nombre (por ejemplo `teleponter`) y pulsa **Create repository**.
2. En la página del repositorio vacío pulsa **uploading an existing file**.
3. Descomprime el ZIP del proyecto y **arrastra todo su contenido** (incluida la carpeta `.github`) a la página. Pulsa **Commit changes**.
   - Si tu explorador oculta la carpeta `.github` porque empieza con punto, actívala en *Ver → Elementos ocultos*. Sin esa carpeta no se compila nada.
4. Ve a la pestaña **Actions**. Verás el proceso «Compilar Teleponter» en marcha; tarda unos 10–15 minutos.
5. Cuando tenga una marca verde, entra en él y baja a **Artifacts**:
   - `Teleponter-windows`: un ZIP. Descomprímelo y ejecuta `teleponter.exe`.
   - `Teleponter-android`: contiene `Teleponter-android.apk`. Pásalo al móvil e instálalo (Android pedirá permitir «instalar apps de origen desconocido»).

Si quieres una página de descargas fija, crea una *Release* con una etiqueta que empiece por `v` (por ejemplo `v1.0.0`) y los instaladores se adjuntarán solos.

## Opción 2: compilar en tu PC con Windows

1. Instala [Flutter](https://docs.flutter.dev/get-started/install/windows) y, para Windows, Visual Studio con la carga de trabajo «Desarrollo para el escritorio con C++». Para Android, instala Android Studio.
2. Abre una terminal en la carpeta del proyecto y ejecuta:

```bash
flutter create --org com.teleponter --project-name teleponter --platforms=windows,android .
del test\widget_test.dart
python tool/patch_platforms.py
flutter pub get
flutter run -d windows           # probar en Windows
flutter build windows --release  # crea build\windows\x64\runner\Release\teleponter.exe
flutter build apk --release      # crea build\app\outputs\flutter-apk\app-release.apk
```

`tool/patch_platforms.py` añade los permisos de micrófono, cámara y red en Android, el `minSdk` 24 y la pantalla siempre encendida.

---

## Notas

- **Permisos**: la primera vez, Android pide micrófono (y cámara si usas *Grabar*). En Windows, revisa *Configuración → Privacidad → Micrófono* y activa *Reconocimiento de voz en línea* si el seguimiento de palabras no responde.
- **Conexión remota y director**: funcionan solo dentro de la misma red Wi-Fi. Windows puede preguntar si permites el acceso a la red: acepta en *redes privadas*. La conexión no está cifrada, así que úsala solo en redes de confianza.
- **Grabar en Android**: algunos móviles no permiten que la cámara grabe audio y que el reconocimiento de voz escuche a la vez. Si al grabar no avanza el resaltado, usa el modo **Clásico**.
- **Keynote / Google Slides**: exporta primero a PowerPoint (.pptx) para importar las notas.

## Estructura del código

```
lib/
  core/        Lógica pura: alineación voz-texto, detector de voz, lector .pptx, ajustes
  services/    Controlador del teleprompter, voz, micrófono, servidores remoto/director, ventana
  ui/          Pantallas: editor, lectura, cámara, ajustes
test/          Pruebas de la lógica (flutter test)
tool/          Script que ajusta las carpetas android/ y windows/
.github/       Compilación automática del .exe y el .apk
```

## Licencia

MIT. Se conserva el aviso de copyright del proyecto original Textream (ver `LICENSE`).
La fuente OpenDyslexic se distribuye bajo la licencia SIL OFL (ver `assets/fonts/OpenDyslexic-OFL.txt`).
