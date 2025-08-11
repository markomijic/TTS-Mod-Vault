import 'dart:io' show Directory, File, Process, stderr;
import 'dart:isolate' show Isolate;
import 'dart:math' show max, min;
import 'dart:io' show Platform;

import 'package:archive/archive.dart' show ZipDecoder;
import 'package:flutter/material.dart' show debugPrint;
import 'package:hooks_riverpod/hooks_riverpod.dart' show Ref, StateNotifier;
import 'package:path/path.dart' as path;
import 'package:tts_mod_vault/src/state/backup/existing_backups_state.dart'
    show ExistingBackupsState;
import 'package:tts_mod_vault/src/state/backup/models/existing_backup_model.dart'
    show ExistingBackup;
import 'package:tts_mod_vault/src/state/mods/mod_model.dart' show Mod;
import 'package:tts_mod_vault/src/state/provider.dart' show directoriesProvider;
import 'package:tts_mod_vault/src/utils.dart' show getBackupFilenameByMod;

class ExistingBackupsStateNotifier extends StateNotifier<ExistingBackupsState> {
  final Ref ref;

  ExistingBackupsStateNotifier(this.ref) : super(ExistingBackupsState.empty());

  Future<void> loadExistingBackups() async {
    debugPrint('loadExistingBackups - started at ${DateTime.now()}');

    final backupsDir = ref.read(directoriesProvider).backupsDir;
    final directory = Directory(backupsDir);

    if (backupsDir.isEmpty || !directory.existsSync()) {
      state = ExistingBackupsState(backups: []);
      return;
    }

    final files = await directory
        .list(recursive: true)
        .where((entity) => entity is File)
        .cast<File>()
        .where((file) => path.extension(file.path).toLowerCase() == '.ttsmod')
        .toList();

    if (files.isEmpty) {
      state = ExistingBackupsState(backups: []);
      return;
    }

    // Split files into ASCII and Unicode groups
    final asciiFiles = <File>[];
    final unicodeFiles = <File>[];

    for (final file in files) {
      if (_containsUnicode(file.path)) {
        unicodeFiles.add(file);
      } else {
        asciiFiles.add(file);
      }
    }

    debugPrint(
        'loadExistingBackups - Processing ${asciiFiles.length} ASCII files in isolates, ${unicodeFiles.length} Unicode files in main thread');

    final numberOfIsolates = max(Platform.numberOfProcessors - 2, 2);
    final chunkedAsciiFiles = _chunkList(asciiFiles, numberOfIsolates);
    final futures = chunkedAsciiFiles
        .map((chunk) => Isolate.run(() => _processBackupFiles(chunk)))
        .toList();

    if (unicodeFiles.isNotEmpty) {
      futures.add(_processBackupFiles(unicodeFiles));
    }

    final results = await Future.wait(futures);
    final backups = results.expand((list) => list).toList();

    state = ExistingBackupsState(backups: backups);
    debugPrint('loadExistingBackups - finished at ${DateTime.now()}');
  }

  bool _containsUnicode(String filePath) {
    final fileName = path.basename(filePath);

    // Check if any character in the filename is outside ASCII range (0-127)
    for (int i = 0; i < fileName.length; i++) {
      if (fileName.codeUnitAt(i) > 127) {
        return true;
      }
    }
    return false;
  }

  List<List<T>> _chunkList<T>(List<T> list, int chunkSize) {
    final chunks = <List<T>>[];
    final itemsPerChunk = (list.length / chunkSize).ceil();

    for (int i = 0; i < list.length; i += itemsPerChunk) {
      final end = min(i + itemsPerChunk, list.length);
      chunks.add(list.sublist(i, end));
    }

    return chunks;
  }

  void addBackup(ExistingBackup newBackup) {
    final existingIndex = state.backups
        .indexWhere((backup) => backup.filename == newBackup.filename);

    if (existingIndex >= 0) {
      // Replace existing backup
      final updatedBackups = [...state.backups];
      updatedBackups[existingIndex] = newBackup;
      state = ExistingBackupsState(backups: updatedBackups);
    } else {
      // Add new backup
      state = ExistingBackupsState(backups: [...state.backups, newBackup]);
    }
  }

  ExistingBackup? _getMostRecentBackupByFilename(String filename) {
    final matchingBackups =
        state.backups.where((backup) => backup.filename == filename).toList();

    if (matchingBackups.isEmpty) {
      return null;
    }

    // Sort by lastModifiedTimestamp in descending order and take the first (most recent)
    matchingBackups.sort(
        (a, b) => b.lastModifiedTimestamp.compareTo(a.lastModifiedTimestamp));

    return matchingBackups.first;
  }

  ExistingBackup? getBackupByMod(Mod mod) {
    try {
      final backupFileName = getBackupFilenameByMod(mod);
      return _getMostRecentBackupByFilename(backupFileName);
    } catch (e) {
      return null;
    }
  }
}

///
/// Top-level functions required by Isolate.run
///
Future<List<ExistingBackup>> _processBackupFiles(List<File> files) async {
  final backups = <ExistingBackup>[];

  for (final file in files) {
    try {
      final stat = await file.stat();
      final filename = path.basename(file.path);
      final totalAssetCount = await listZipContents(file.path);

      backups.add(ExistingBackup(
        filename: filename,
        filepath: path.normalize(file.path),
        lastModifiedTimestamp: stat.modified.millisecondsSinceEpoch ~/ 1000,
        totalAssetCount: totalAssetCount,
      ));
    } catch (e) {
      debugPrint("_processBackupFiles error $e");
    }
  }

  return backups;
}

Future<int?> listZipContents(String zipPath) async {
  List<String> filePaths;
  if (Platform.isWindows) {
    filePaths = await _listWithTar(zipPath);
  } else {
    filePaths = await _listWithUnzip(zipPath);
  }

  final folderCounts = <String, int>{};
  for (final path in filePaths) {
    if (path.endsWith('/')) continue; // Skip folders
    final folder =
        path.contains('/') ? path.substring(0, path.lastIndexOf('/')) : 'root';
    folderCounts.update(folder, (count) => count + 1, ifAbsent: () => 1);
  }

  // Calculate total for asset folders
  const assetFolders = ['Assetbundles', 'Audio', 'Images', 'PDF', 'Models'];
  final assetTotal = assetFolders
      .map((folder) => folderCounts['Mods/$folder'] ?? 0)
      .fold(0, (a, b) => a + b);

  return assetTotal;
}

Future<List<String>> _listWithUnzip(String zipPath) async {
  try {
    final result = await Process.run('unzip', ['-Z1', zipPath]);

    if (result.exitCode != 0) {
      stderr.writeln('_listWithUnzip result error: ${result.stderr}');
      return _fallbackToDartZip(zipPath);
    }

    final lines = (result.stdout as String).split('\n');
    return lines.where((line) => line.trim().isNotEmpty).toList();
  } catch (e) {
    stderr.writeln('_listWithUnzip error: $e');
    return _fallbackToDartZip(zipPath);
  }
}

Future<List<String>> _listWithTar(String zipPath) async {
  try {
    final result = await Process.run('tar', ['-tf', zipPath]);

    if (result.exitCode != 0) {
      stderr.writeln('_listWithTar result error: ${result.stderr}');
      return _fallbackToDartZip(zipPath);
    }

    final lines = (result.stdout as String).split('\n');
    return lines.where((line) => line.trim().isNotEmpty).toList();
  } catch (e) {
    stderr.writeln('_listWithTar error: $e');
    return _fallbackToDartZip(zipPath);
  }
}

Future<List<String>> _fallbackToDartZip(String zipPath) async {
  stderr.writeln('Falling back to Dart archive package for: $zipPath');

  try {
    final bytes = await File(zipPath).readAsBytes();
    final archive = ZipDecoder().decodeBytes(bytes);

    return archive.files
        // Normalize to forward slashes to align with Tar and Unzip methods
        .map((file) => file.name.trim().replaceAll('\\', '/'))
        .where((name) => name.isNotEmpty)
        .toList();
  } catch (e) {
    stderr.writeln('_fallbackToDartZip error: $e');
    return [];
  }
}
