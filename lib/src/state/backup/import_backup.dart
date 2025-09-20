import 'dart:io';

import 'package:archive/archive.dart' show ZipDecoder;
import 'package:file_picker/file_picker.dart'
    show FilePicker, FilePickerResult, FileType;
import 'package:flutter/material.dart' show debugPrint;
import 'package:hooks_riverpod/hooks_riverpod.dart' show Ref, StateNotifier;
import 'package:path/path.dart' as p
    show basenameWithoutExtension, extension, normalize, split;
import 'package:tts_mod_vault/src/state/backup/import_backup_state.dart'
    show ImportBackupState, ImportBackupStatusEnum;
import 'package:tts_mod_vault/src/state/provider.dart' show directoriesProvider;

class ImportBackupNotifier extends StateNotifier<ImportBackupState> {
  final Ref ref;

  ImportBackupNotifier(this.ref) : super(const ImportBackupState());

  Future<bool> importBackup() async {
    try {
      state = state.copyWith(
        status: ImportBackupStatusEnum.awaitingBackupFile,
        lastImportedJsonFileName: "",
        currentCount: 0,
        totalCount: 0,
      );

      final backupsDir = ref.read(directoriesProvider).backupsDir;

      FilePickerResult? result;
      try {
        result = await FilePicker.platform.pickFiles(
          type: FileType.custom,
          lockParentWindow: true,
          initialDirectory: backupsDir.isEmpty ? null : backupsDir,
          allowedExtensions: ['ttsmod'],
          allowMultiple: false,
        );
      } catch (e) {
        debugPrint("importBackup - file picker error: $e");
        return false;
      }

      if (result == null || result.files.isEmpty) {
        state = state.copyWith(
          status: ImportBackupStatusEnum.idle,
        );
        return false;
      }

      final filePath = result.files.single.path ?? '';
      if (filePath.isEmpty) {
        state = state.copyWith(
          status: ImportBackupStatusEnum.idle,
        );
        return false;
      }

      state = state.copyWith(
        status: ImportBackupStatusEnum.importingBackup,
        importFileName: p.basenameWithoutExtension(result.files.single.name),
      );

      final bytes = await File(filePath).readAsBytes();
      final archive = ZipDecoder().decodeBytes(bytes);
      final modsDir = Directory(ref.read(directoriesProvider).modsDir);
      final savesDir = Directory(ref.read(directoriesProvider).savesDir);

      for (final file in archive) {
        if (file.isFile) {
          final filename = file.name;
          String targetDir = modsDir.parent.path;

          if (filename.startsWith('Mods')) {
            targetDir = modsDir.parent.path;
          } else if (filename.startsWith('Saves')) {
            targetDir = savesDir.parent.path;
          }

          final data = file.content as List<int>;
          final outputFile = File('$targetDir/$filename');

          if (_isJsonFile(filename)) {
            state = state.copyWith(
                lastImportedJsonFileName: p.basenameWithoutExtension(filename));
          }

          try {
            state = state.copyWith(
                currentCount: archive.files.indexOf(file) + 1,
                totalCount: archive.files.length);
            await outputFile.create(recursive: true);
            await outputFile.writeAsBytes(data);
          } catch (e) {
            debugPrint(
                'importBackup failed for $filename because of error: $e');
          }
        }
      }
    } catch (e) {
      debugPrint('importBackup error: $e');
      state = state.copyWith(
        status: ImportBackupStatusEnum.idle,
        importFileName: "",
      );
      return false;
    }

    state = state.copyWith(
      status: ImportBackupStatusEnum.idle,
      importFileName: "",
    );
    return true;
  }

  void resetLastImportedJsonFileName() {
    state = state.copyWith(lastImportedJsonFileName: "");
  }

  bool _isJsonFile(String inputPath) {
    final filePath = p.normalize(inputPath);

    final isJsonFile = p.extension(filePath).toLowerCase() == '.json';
    final containsWorkshop = p.split(filePath).contains('Workshop');

    return isJsonFile && containsWorkshop;
  }
}
