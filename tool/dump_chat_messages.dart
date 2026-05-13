// ignore_for_file: avoid_print

import 'dart:convert';
import 'dart:io';

import 'package:hive_ce/hive.dart';
import 'package:path/path.dart' as p;

Future<void> main(List<String> args) async {
  final home = Platform.environment['HOME'];
  if (home == null || home.isEmpty) {
    stderr.writeln('HOME is not available.');
    exitCode = 1;
    return;
  }

  final userHome = _macOsUserHome(home);
  final baseDir = args.isNotEmpty
      ? Directory(args.first)
      : Directory(
          p.join(
            userHome,
            'Library',
            'Application Support',
            'BB Planet Desktop',
          ),
        );
  final secureFile = File(p.join(baseDir.path, 'secure_store_fallback.json'));
  final cacheDir = Directory(p.join(baseDir.path, 'cache'));
  final hiveFile = File(p.join(cacheDir.path, 'chat_messages_v1.hive'));
  final profileHiveFile = File(
    p.join(cacheDir.path, 'chat_peer_profiles_v1.hive'),
  );
  final appAccountHistoryHiveFile = File(
    p.join(cacheDir.path, 'app_account_login_history_v1.hive'),
  );

  print('baseDir: ${baseDir.path}');
  print('hive: ${hiveFile.existsSync() ? hiveFile.path : 'missing'}');
  if (!secureFile.existsSync() || !hiveFile.existsSync()) {
    return;
  }

  final secureJson =
      jsonDecode(await secureFile.readAsString()) as Map<String, dynamic>;
  final rawKey = secureJson['chat.messageCache.encryptionKey']?.toString();
  if (rawKey == null || rawKey.isEmpty) {
    print('encryption key: missing');
    return;
  }

  final snapshotDir = await Directory.systemTemp.createTemp(
    'bb_planet_chat_messages_',
  );
  final snapshotHive = File(p.join(snapshotDir.path, 'chat_messages_v1.hive'));
  await hiveFile.copy(snapshotHive.path);

  Hive.init(snapshotDir.path);
  final box = await Hive.openBox<String>(
    'chat_messages_v1',
    encryptionCipher: HiveAesCipher(_normalizeKey(rawKey)),
  );

  final messages = <Map<String, dynamic>>[];
  for (final raw in box.values) {
    final decoded = jsonDecode(raw);
    if (decoded is Map) {
      messages.add(
        decoded.map((key, value) => MapEntry(key.toString(), value)),
      );
    }
  }
  print('records: ${messages.length}');

  final groups = <String, List<Map<String, dynamic>>>{};
  for (final message in messages) {
    final appUserId = message['appUserId'];
    final peerUserId = message['peerUserId'];
    final key = 'sender:$appUserId -> peer:$peerUserId';
    groups.putIfAbsent(key, () => []).add(message);
  }

  final sortedEntries = groups.entries.toList()
    ..sort((left, right) => right.value.length.compareTo(left.value.length));
  for (final entry in sortedEntries) {
    entry.value.sort(
      (left, right) =>
          _dateOf(left['createdAt']).compareTo(_dateOf(right['createdAt'])),
    );
    final last = entry.value.last;
    print('');
    print('${entry.key} records=${entry.value.length}');
    print(
      'last ${last['direction']} ${last['sendStatus']} '
      '${last['createdAt']} room=${last['roomId']} '
      'local=${last['localId']} server=${last['serverMessageId']}',
    );
    print('text: ${_preview(last['text']?.toString() ?? '')}');
  }

  await box.close();
  if (profileHiveFile.existsSync()) {
    final snapshotProfileHive = File(
      p.join(snapshotDir.path, 'chat_peer_profiles_v1.hive'),
    );
    await profileHiveFile.copy(snapshotProfileHive.path);
    final profileBox = await Hive.openBox<String>(
      'chat_peer_profiles_v1',
      encryptionCipher: HiveAesCipher(_normalizeKey(rawKey)),
    );
    print('');
    print('profiles: ${profileBox.length}');
    for (final raw in profileBox.values) {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) {
        continue;
      }
      final profile = decoded.map(
        (key, value) => MapEntry(key.toString(), value),
      );
      print(
        'sender:${profile['appUserId']} -> peer:${profile['peerUserId']} '
        'name=${profile['displayName']} avatar=${profile['avatarUrl']}',
      );
    }
    await profileBox.close();
  }
  if (appAccountHistoryHiveFile.existsSync()) {
    final rawHistoryKey = secureJson['appAccount.history.encryptionKey']
        ?.toString();
    if (rawHistoryKey != null && rawHistoryKey.isNotEmpty) {
      final snapshotHistoryHive = File(
        p.join(snapshotDir.path, 'app_account_login_history_v1.hive'),
      );
      await appAccountHistoryHiveFile.copy(snapshotHistoryHive.path);
      final historyBox = await Hive.openBox<String>(
        'app_account_login_history_v1',
        encryptionCipher: HiveAesCipher(_normalizeKey(rawHistoryKey)),
      );
      print('');
      print('app account history: ${historyBox.length}');
      for (final raw in historyBox.values) {
        final decoded = jsonDecode(raw);
        if (decoded is! Map) {
          continue;
        }
        final account = decoded.map(
          (key, value) => MapEntry(key.toString(), value),
        );
        print(
          'id=${account['id']} email=${account['email']} '
          'avatar=${(account['avatarUrl']?.toString() ?? '').isNotEmpty} '
          'token=${(account['token']?.toString() ?? '').isNotEmpty}',
        );
      }
      await historyBox.close();
    }
  }
  await snapshotDir.delete(recursive: true);
}

List<int> _normalizeKey(String rawKey) {
  final source = utf8.encode(rawKey);
  return List<int>.generate(32, (index) {
    if (index < source.length) {
      return source[index];
    }
    return 0;
  });
}

String _macOsUserHome(String home) {
  const containerMarker = '/Library/Containers/';
  final markerIndex = home.indexOf(containerMarker);
  if (markerIndex > 0) {
    return home.substring(0, markerIndex);
  }
  return home;
}

DateTime _dateOf(Object? value) {
  return DateTime.tryParse(value?.toString() ?? '') ??
      DateTime.fromMillisecondsSinceEpoch(0);
}

String _preview(String text) {
  final compact = text.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (compact.length <= 120) {
    return compact;
  }
  return '${compact.substring(0, 120)}...';
}
