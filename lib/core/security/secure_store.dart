import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../storage/desktop_data_directory.dart';

class SecureStore {
  const SecureStore({
    FlutterSecureStorage storage = const FlutterSecureStorage(),
  }) : _storage = storage;

  final FlutterSecureStorage _storage;

  Future<String?> read(String key) async {
    try {
      final value = await _storage.read(key: key);
      if (value != null) {
        return value;
      }
      final values = await _readFallbackValues();
      return values[key];
    } catch (_) {
      final values = await _readFallbackValues();
      return values[key];
    }
  }

  Future<void> write(String key, String value) async {
    try {
      await _storage.write(key: key, value: value);
    } catch (_) {
      // Keep the file fallback below as the desktop source of recovery.
    }
    final values = await _readFallbackValues();
    values[key] = value;
    await _writeFallbackValues(values);
  }

  Future<void> delete(String key) async {
    try {
      await _storage.delete(key: key);
    } catch (_) {
      // Keep deleting the fallback copy below.
    }
    final values = await _readFallbackValues();
    values.remove(key);
    await _writeFallbackValues(values);
  }

  Future<File> _fallbackFile() async {
    final directory = await DesktopDataDirectory.resolve();
    return File('${directory.path}/secure_store_fallback.json');
  }

  Future<Map<String, String>> _readFallbackValues() async {
    final file = await _fallbackFile();
    if (!await file.exists()) {
      return <String, String>{};
    }

    final raw = await file.readAsString();
    final decoded = jsonDecode(raw);
    if (decoded is! Map) {
      return <String, String>{};
    }

    return decoded.map(
      (key, value) => MapEntry(key.toString(), value.toString()),
    );
  }

  Future<void> _writeFallbackValues(Map<String, String> values) async {
    final file = await _fallbackFile();
    await file.parent.create(recursive: true);
    await file.writeAsString(jsonEncode(values));
  }
}
