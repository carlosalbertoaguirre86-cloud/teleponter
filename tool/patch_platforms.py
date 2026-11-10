#!/usr/bin/env python3
"""Ajusta las carpetas android/ y windows/ generadas por `flutter create`.

Se ejecuta después de:
  flutter create --org com.teleponter --project-name teleponter --platforms=android,windows .

Es idempotente: se puede ejecutar varias veces sin duplicar cambios.
"""
import glob
import os
import re
import shutil
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def read(path):
    with open(path, encoding="utf-8") as f:
        return f.read()


def write(path, text):
    with open(path, "w", encoding="utf-8", newline="") as f:
        f.write(text)


def patch_android():
    manifest = os.path.join(ROOT, "android", "app", "src", "main", "AndroidManifest.xml")
    if not os.path.exists(manifest):
        print("android/ no existe, se omite")
        return
    m = read(manifest)
    perms = [
        '<uses-permission android:name="android.permission.INTERNET"/>',
        '<uses-permission android:name="android.permission.RECORD_AUDIO"/>',
        '<uses-permission android:name="android.permission.CAMERA"/>',
        '<uses-permission android:name="android.permission.ACCESS_NETWORK_STATE"/>',
        '<uses-permission android:name="android.permission.ACCESS_WIFI_STATE"/>',
        '<uses-permission android:name="android.permission.BLUETOOTH"/>',
        '<uses-permission android:name="android.permission.BLUETOOTH_CONNECT"/>',
        '<uses-permission android:name="android.permission.SYSTEM_ALERT_WINDOW"/>',
        '<uses-permission android:name="android.permission.FOREGROUND_SERVICE"/>',
        '<uses-permission android:name="android.permission.FOREGROUND_SERVICE_SPECIAL_USE"/>',
        '<uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>',
    ]
    for p in perms:
        name = re.search(r'android:name="([^"]+)"', p).group(1)
        if name not in m:
            m = re.sub(r"(<manifest[^>]*>)", r"\1\n    " + p, m, count=1)
    speech_query = '<action android:name="android.speech.RecognitionService" />'
    if speech_query not in m:
        block = (
            "\n        <intent>\n            " + speech_query + "\n        </intent>"
        )
        if "<queries>" in m:
            m = m.replace("<queries>", "<queries>" + block, 1)
        else:
            m = m.replace(
                "</manifest>", "    <queries>" + block + "\n    </queries>\n</manifest>", 1
            )
    overlay_service = "flutter.overlay.window.flutter_overlay_window.OverlayService"
    if overlay_service not in m:
        m = m.replace(
            "</application>",
            '    <service android:name="' + overlay_service + '"\n'
            '            android:exported="false"\n'
            '            android:foregroundServiceType="specialUse">\n'
            '            <property android:name="android.app.PROPERTY_SPECIAL_USE_FGS_SUBTYPE"\n'
            '                android:value="Teleprompter flotante sobre otras apps"/>\n'
            "        </service>\n"
            "    </application>",
            1,
        )
    m = re.sub(r'android:label="[^"]*"', 'android:label="Teleponter"', m, count=1)
    if "requestLegacyExternalStorage" not in m:
        m = m.replace("<application", '<application\n        android:requestLegacyExternalStorage="true"', 1)
    write(manifest, m)
    print("AndroidManifest.xml actualizado")

    for gradle in glob.glob(os.path.join(ROOT, "android", "app", "build.gradle*")):
        g = read(gradle)
        g = re.sub(r"minSdk(Version)?\s*=?\s*flutter\.minSdkVersion", "minSdk = 24", g)
        g = re.sub(r"minSdkVersion\s+flutter\.minSdkVersion", "minSdkVersion 24", g)
        write(gradle, g)
        print("minSdk = 24 en", os.path.basename(gradle))

    for act in glob.glob(
        os.path.join(ROOT, "android", "app", "src", "main", "kotlin", "**", "MainActivity.kt"),
        recursive=True,
    ):
        k = read(act)
        if "FLAG_KEEP_SCREEN_ON" not in k:
            pkg = re.search(r"^package\s+(\S+)", k, re.M).group(1)
            k = (
                f"package {pkg}\n\n"
                "import android.os.Bundle\n"
                "import android.view.WindowManager\n"
                "import io.flutter.embedding.android.FlutterActivity\n\n"
                "class MainActivity : FlutterActivity() {\n"
                "    override fun onCreate(savedInstanceState: Bundle?) {\n"
                "        super.onCreate(savedInstanceState)\n"
                "        // Mantener la pantalla encendida mientras se lee el guion.\n"
                "        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)\n"
                "    }\n"
                "}\n"
            )
            write(act, k)
            print("MainActivity.kt: pantalla siempre encendida")


def patch_windows():
    main_cpp = os.path.join(ROOT, "windows", "runner", "main.cpp")
    if not os.path.exists(main_cpp):
        print("windows/ no existe, se omite")
        return
    c = read(main_cpp)
    c = c.replace('L"teleponter"', 'L"Teleponter"')
    write(main_cpp, c)
    rc = os.path.join(ROOT, "windows", "runner", "Runner.rc")
    if os.path.exists(rc):
        r = read(rc)
        r = r.replace('"teleponter"', '"Teleponter"')
        write(rc, r)
    print("Runner de Windows actualizado")


def install_signing_key():
    """Usa siempre la misma firma para el .apk.

    Sin esto, cada compilación de GitHub crea una clave nueva y Android no
    deja instalar la versión nueva encima de la anterior.
    """
    src = os.path.join(ROOT, "tool", "debug.keystore")
    if not os.path.exists(src):
        return
    dst_dir = os.path.join(os.path.expanduser("~"), ".android")
    os.makedirs(dst_dir, exist_ok=True)
    shutil.copyfile(src, os.path.join(dst_dir, "debug.keystore"))
    print("Clave de firma fija instalada")


if __name__ == "__main__":
    install_signing_key()
    patch_android()
    patch_windows()
    sys.exit(0)
