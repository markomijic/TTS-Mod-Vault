import 'dart:io';

import 'package:file_picker/file_picker.dart'
    show FilePicker, FilePickerResult, FileType;
import 'package:flutter/material.dart' show debugPrint;
import 'package:archive/archive.dart' show ZipDecoder;
import 'package:riverpod/riverpod.dart' show Ref, StateNotifier;
import 'package:tts_mod_vault/src/state/backup/backup_state.dart'
    show BackupState;

class BackupNotifier extends StateNotifier<BackupState> {
  final Ref ref;

  BackupNotifier(this.ref) : super(const BackupState());

  Future<bool> importBackup(String targetDir) async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['ttsmod'],
        allowMultiple: false,
      );

      if (result == null || result.files.isEmpty) {
        return false;
      }

      final filePath = result.files.single.path!;
      if (filePath.isEmpty) {
        return false;
      }

      state = state.copyWith(importInProgress: true);

      final bytes = await File(filePath).readAsBytes();
      final archive = ZipDecoder().decodeBytes(bytes);

      for (final file in archive) {
        if (file.isFile) {
          final filename = file.name;
          final data = file.content as List<int>;
          final outputFile = File('$targetDir/$filename');

          try {
            await outputFile.writeAsBytes(data);
          } catch (e) {
            debugPrint(
                'importBackup failed for $filename because of error: $e');
          }
        }
      }
    } catch (e) {
      debugPrint('importBackup error: $e');
      return false;
    }

    state = state.copyWith(importInProgress: false);
    return true;
  }
}
