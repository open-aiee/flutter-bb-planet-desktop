import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class DesktopDataDirectory {
  const DesktopDataDirectory._();

  static const appFolderName = 'BB Planet Desktop';

  static Future<Directory> resolve() async {
    final explicit = Platform.environment['BB_PLANET_DESKTOP_DATA_DIR'];
    if (explicit != null && explicit.trim().isNotEmpty) {
      return Directory(explicit.trim());
    }

    if (Platform.isMacOS) {
      final home = Platform.environment['HOME'];
      if (home != null && home.trim().isNotEmpty) {
        final directory = Directory(
          p.join(home.trim(), 'Library', 'Application Support', appFolderName),
        );
        await _copyMissingFiles(
          from: Directory(
            p.join(
              home.trim(),
              'Library',
              'Containers',
              'com.example.flutterBbPlanetDesktop',
              'Data',
              'Library',
              'Application Support',
              appFolderName,
            ),
          ),
          to: directory,
        );
        return directory;
      }
    }

    if (Platform.isWindows) {
      final appData = Platform.environment['APPDATA'];
      if (appData != null && appData.trim().isNotEmpty) {
        return Directory(p.join(appData.trim(), appFolderName));
      }
    }

    if (Platform.isLinux) {
      final dataHome = Platform.environment['XDG_DATA_HOME'];
      if (dataHome != null && dataHome.trim().isNotEmpty) {
        return Directory(p.join(dataHome.trim(), 'bb-planet-desktop'));
      }
      final home = Platform.environment['HOME'];
      if (home != null && home.trim().isNotEmpty) {
        return Directory(
          p.join(home.trim(), '.local', 'share', 'bb-planet-desktop'),
        );
      }
    }

    final fallback = await getApplicationSupportDirectory();
    return Directory(p.join(fallback.path, appFolderName));
  }

  static Future<void> _copyMissingFiles({
    required Directory from,
    required Directory to,
  }) async {
    if (!await from.exists()) {
      return;
    }

    await for (final entity in from.list(recursive: true)) {
      if (entity is! File) {
        continue;
      }
      final relativePath = p.relative(entity.path, from: from.path);
      final target = File(p.join(to.path, relativePath));
      if (await target.exists()) {
        continue;
      }
      await target.parent.create(recursive: true);
      await entity.copy(target.path);
    }
  }
}
