import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'desktop_data_directory.dart';

final chatOpsSqliteDatabaseProvider = FutureProvider<Database>((ref) async {
  final database = await ChatOpsSqliteDatabase.open();
  ref.onDispose(() {
    database.close();
  });
  return database;
});

class ChatOpsSqliteDatabase {
  const ChatOpsSqliteDatabase._();

  static const fileName = 'chat_ops.sqlite';
  static bool _initialized = false;

  static Future<Database> open() async {
    _ensureInitialized();

    final root = await DesktopDataDirectory.resolve();
    final cacheDir = Directory(p.join(root.path, 'cache'));
    if (!await cacheDir.exists()) {
      await cacheDir.create(recursive: true);
    }

    final databasePath = p.join(cacheDir.path, fileName);
    debugPrint('[CHAT_OPS][LOCAL][SQLITE] open path=$databasePath');

    return databaseFactory.openDatabase(
      databasePath,
      options: OpenDatabaseOptions(
        version: 1,
        onConfigure: (db) async {
          await db.execute('PRAGMA foreign_keys = ON');
          await db.execute('PRAGMA journal_mode = WAL');
        },
        onCreate: (db, version) async {
          await _createSchema(db);
        },
      ),
    );
  }

  static void _ensureInitialized() {
    if (_initialized) {
      return;
    }
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    _initialized = true;
  }

  static Future<void> _createSchema(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS chat_messages (
        app_user_id INTEGER NOT NULL,
        peer_user_id INTEGER NOT NULL,
        local_id TEXT NOT NULL,
        conversation_key TEXT NOT NULL,
        room_id INTEGER,
        direction TEXT NOT NULL,
        text TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        send_status TEXT NOT NULL,
        client_message_id TEXT,
        server_message_id TEXT,
        error_message TEXT,
        send_type INTEGER NOT NULL DEFAULT 1,
        msg_data TEXT,
        local_media_path TEXT,
        PRIMARY KEY (app_user_id, peer_user_id, local_id)
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_chat_messages_conversation '
      'ON chat_messages (app_user_id, peer_user_id, created_at)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_chat_messages_room '
      'ON chat_messages (app_user_id, room_id)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_chat_messages_server '
      'ON chat_messages (app_user_id, peer_user_id, server_message_id)',
    );

    await db.execute('''
      CREATE TABLE IF NOT EXISTS chat_peer_profiles (
        app_user_id INTEGER NOT NULL,
        peer_user_id INTEGER NOT NULL,
        display_name TEXT NOT NULL,
        avatar_url TEXT NOT NULL,
        updated_at INTEGER NOT NULL,
        PRIMARY KEY (app_user_id, peer_user_id)
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_chat_peer_profiles_app '
      'ON chat_peer_profiles (app_user_id, peer_user_id)',
    );
  }
}
