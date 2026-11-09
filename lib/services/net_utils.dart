import 'dart:io';
import 'dart:math';

/// IPv4 de la red local más probable (Wi-Fi / Ethernet).
Future<String> localIpAddress() async {
  try {
    final interfaces = await NetworkInterface.list(
      type: InternetAddressType.IPv4,
      includeLoopback: false,
    );
    String? fallback;
    for (final iface in interfaces) {
      final name = iface.name.toLowerCase();
      final virtual = name.contains('vmware') ||
          name.contains('virtual') ||
          name.contains('vbox') ||
          name.contains('docker') ||
          name.contains('wsl') ||
          name.contains('hyper-v') ||
          name.startsWith('rmnet') ||
          name.startsWith('tun');
      for (final addr in iface.addresses) {
        final ip = addr.address;
        if (ip.startsWith('169.254.')) continue;
        final private = ip.startsWith('192.168.') ||
            ip.startsWith('10.') ||
            RegExp(r'^172\.(1[6-9]|2\d|3[01])\.').hasMatch(ip);
        if (private && !virtual) return ip;
        fallback ??= ip;
      }
    }
    return fallback ?? '127.0.0.1';
  } catch (_) {
    return '127.0.0.1';
  }
}

String randomToken([int length = 10]) {
  const chars = 'abcdefghjkmnpqrstuvwxyz23456789';
  final r = Random.secure();
  return List.generate(length, (_) => chars[r.nextInt(chars.length)]).join();
}
