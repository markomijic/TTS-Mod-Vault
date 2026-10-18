import 'dart:io' show Directory;

import 'package:path/path.dart' as p;
import 'package:tts_mod_vault/domain/constants.dart';
import 'package:tts_mod_vault/domain/models/directories.dart';

/// Injectable "does this directory exist" check so the rules below stay
/// testable without touching the disk.
typedef DirectoryExists = bool Function(String path);

bool _ioDirectoryExists(String path) => Directory(path).existsSync();

/// Default Tabletop Simulator data folder for [platform]
/// (`Platform.operatingSystem` values: `windows`, `macos`, `linux`).
///
/// - Windows: `<home>/Documents/My Games/Tabletop Simulator`
/// - macOS: `<home>/Library/Tabletop Simulator`
/// - Linux: the Steam snap location
///   `<home>/snap/steam/common/.local/share/Tabletop Simulator` when it
///   exists, otherwise `<home>/.local/share/Tabletop Simulator`.
///
/// Unknown platforms are treated like Linux. Paths are joined with the
/// separator of [platform], not of the host, so the result is deterministic
/// in tests.
String defaultTtsDirectory({
  required String platform,
  required String home,
  DirectoryExists? directoryExists,
}) {
  final exists = directoryExists ?? _ioDirectoryExists;
  final ctx = _contextFor(platform);
  switch (platform) {
    case 'windows':
      return ctx.joinAll([home, 'Documents', 'My Games', 'Tabletop Simulator']);
    case 'macos':
      return ctx.joinAll([home, 'Library', 'Tabletop Simulator']);
    default:
      final snap = ctx.joinAll([
        home,
        'snap',
        'steam',
        'common',
        '.local',
        'share',
        'Tabletop Simulator',
      ]);
      if (exists(snap)) return snap;
      return ctx.joinAll([home, '.local', 'share', 'Tabletop Simulator']);
  }
}

/// The default [Directories] for a fresh install: `Mods` and `Saves` under
/// [defaultTtsDirectory], no backups folder.
Directories defaultDirectories({
  required String platform,
  required String home,
  DirectoryExists? directoryExists,
}) {
  final ctx = _contextFor(platform);
  final tts = defaultTtsDirectory(
    platform: platform,
    home: home,
    directoryExists: directoryExists,
  );
  return Directories(
    modsDir: ctx.join(tts, ttsModsFolder),
    savesDir: ctx.join(tts, ttsSavesFolder),
  );
}

/// Validates a user-picked Mods folder.
///
/// Accepts [picked] itself when it exists and is named `Mods`; otherwise
/// accepts a `Mods` child of [picked] when that exists. Returns the resolved,
/// normalised directory or null when neither matches.
String? resolveModsDir(String picked, {DirectoryExists? directoryExists}) =>
    _resolveNamedDir(picked, ttsModsFolder, directoryExists);

/// Validates a user-picked Saves folder.
///
/// With [allowCustomPath] any existing directory is accepted as is (the
/// "custom saves folder" setting). Otherwise the same rule as
/// [resolveModsDir] applies with `Saves`.
String? resolveSavesDir(
  String picked, {
  bool allowCustomPath = false,
  DirectoryExists? directoryExists,
}) {
  if (allowCustomPath) {
    final exists = directoryExists ?? _ioDirectoryExists;
    final normalized = p.normalize(picked);
    return exists(normalized) ? normalized : null;
  }
  return _resolveNamedDir(picked, ttsSavesFolder, directoryExists);
}

String? _resolveNamedDir(
  String picked,
  String folderName,
  DirectoryExists? directoryExists,
) {
  final exists = directoryExists ?? _ioDirectoryExists;
  final normalized = p.normalize(picked);
  if (!exists(normalized)) return null;
  if (p.basename(normalized) == folderName) return normalized;
  final child = p.join(normalized, folderName);
  return exists(child) ? child : null;
}

p.Context _contextFor(String platform) =>
    platform == 'windows' ? p.windows : p.posix;
