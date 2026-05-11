import 'dart:math';

import 'secure_store.dart';

class DesktopDeviceId {
  const DesktopDeviceId({required SecureStore secureStore})
    : _secureStore = secureStore;

  static const key = 'desktop.deviceId';

  final SecureStore _secureStore;

  Future<String> getOrCreate() async {
    final saved = await _secureStore.read(key);
    if (saved != null && saved.isNotEmpty) {
      return saved;
    }

    final random = Random.secure();
    final buffer = StringBuffer('desktop-');
    buffer.write(DateTime.now().millisecondsSinceEpoch.toRadixString(16));
    buffer.write('-');
    for (var i = 0; i < 12; i++) {
      buffer.write(random.nextInt(16).toRadixString(16));
    }
    final value = buffer.toString();
    await _secureStore.write(key, value);
    return value;
  }
}
