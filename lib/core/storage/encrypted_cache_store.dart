import 'dart:convert';
import 'dart:io';

import 'package:hive_ce/hive.dart';
import 'package:path/path.dart' as p;

import 'desktop_data_directory.dart';

class EncryptedCacheStore {
  EncryptedCacheStore({required this.encryptionKey});

  final List<int> encryptionKey;

  Future<Box<String>> openBox(String name) async {
    final directory = await DesktopDataDirectory.resolve();
    final cacheDirectory = Directory(p.join(directory.path, 'cache'));
    await cacheDirectory.create(recursive: true);
    Hive.init(cacheDirectory.path);

    return Hive.openBox<String>(
      name,
      encryptionCipher: HiveAesCipher(encryptionKey),
    );
  }

  static List<int> normalizeKey(String rawKey) {
    final source = utf8.encode(rawKey);
    return List<int>.generate(32, (index) {
      if (index < source.length) {
        return source[index];
      }
      return 0;
    });
  }
}
