import 'dart:io' show Platform, Process;

import 'package:path/path.dart' as p;

/// Reveals [path] in the OS file manager: Windows Explorer with the file
/// selected, macOS Finder with the file revealed, or the parent folder
/// through `xdg-open` elsewhere. Port of 2.x `openInFileExplorer`.
///
/// Returns false when the process could not be started. Explorer's exit code
/// is not checked: it reports 1 even when the window opened.
Future<bool> openInFileExplorer(String path) async {
  final normalized = p.normalize(path);
  try {
    if (Platform.isWindows) {
      await Process.run('explorer.exe', ['/select,', normalized]);
      return true;
    }
    if (Platform.isMacOS) {
      final result = await Process.run('open', ['-R', normalized]);
      return result.exitCode == 0;
    }
    final result = await Process.run('xdg-open', [p.dirname(normalized)]);
    return result.exitCode == 0;
  } on Object {
    return false;
  }
}
