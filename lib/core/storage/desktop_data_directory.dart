import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class DesktopDataDirectory {
  const DesktopDataDirectory._();

  static const appFolderName = 'BB Planet Desktop';

  static Future<Directory> resolve() async {
    if (Platform.isMacOS) {
      final home = _macOsUserHome();
      if (home != null && home.trim().isNotEmpty) {
        return Directory(
          p.join(home.trim(), 'Library', 'Application Support', appFolderName),
        );
      }
      final user = Platform.environment['USER']?.trim();
      if (user != null && user.isNotEmpty) {
        return Directory(
          p.join(
            '/Users',
            user,
            'Library',
            'Application Support',
            appFolderName,
          ),
        );
      }
      throw StateError('Unable to resolve macOS user data directory.');
    }

    final explicit = Platform.environment['BB_PLANET_DESKTOP_DATA_DIR'];
    if (explicit != null && explicit.trim().isNotEmpty) {
      return Directory(explicit.trim());
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

  static String? _macOsUserHome() {
    final home = Platform.environment['HOME']?.trim();
    if (home == null || home.isEmpty) {
      return null;
    }

    const containerMarker = '/Library/Containers/';
    final markerIndex = home.indexOf(containerMarker);
    if (markerIndex > 0) {
      return home.substring(0, markerIndex);
    }
    return home;
  }
}
