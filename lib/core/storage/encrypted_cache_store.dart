import 'dart:convert';

import 'package:hive_ce/hive.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class EncryptedCacheStore {
  EncryptedCacheStore({required this.encryptionKey});

  final List<int> encryptionKey;

  Future<Box<String>> openBox(String name) async {
    final directory = await getApplicationSupportDirectory();
    Hive.init(p.join(directory.path, 'cache'));

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
