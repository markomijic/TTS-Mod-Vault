// A `FilePickerService` double returning fixed paths and recording the
// initial directories it was opened with.

import 'package:tts_mod_vault/features/backups/presentation/file_picker_service.dart';

/// Returns [ttsmodFiles], [jsonFile] and [pngFile]; throws [error] from
/// every method when set.
final class FakeFilePickerService implements FilePickerService {
  FakeFilePickerService({
    this.ttsmodFiles = const [],
    this.jsonFile,
    this.pngFile,
    this.error,
  });

  /// Answer of `pickTtsmodFiles`.
  List<String> ttsmodFiles;

  /// Answer of `pickJsonFile`.
  String? jsonFile;

  /// Answer of `pickPngFile`.
  String? pngFile;

  /// Thrown by every method when set.
  Object? error;

  /// Initial directories passed to `pickTtsmodFiles`.
  final List<String?> ttsmodInitialDirectories = [];

  /// How often each picker was opened.
  int jsonPicks = 0;
  int pngPicks = 0;

  void _maybeThrow() {
    if (error case final e?) throw e;
  }

  @override
  Future<List<String>> pickTtsmodFiles({
    String? dialogTitle,
    String? initialDirectory,
  }) async {
    _maybeThrow();
    ttsmodInitialDirectories.add(initialDirectory);
    return ttsmodFiles;
  }

  @override
  Future<String?> pickJsonFile({
    String? dialogTitle,
    String? initialDirectory,
  }) async {
    _maybeThrow();
    jsonPicks++;
    return jsonFile;
  }

  @override
  Future<String?> pickPngFile({
    String? dialogTitle,
    String? initialDirectory,
  }) async {
    _maybeThrow();
    pngPicks++;
    return pngFile;
  }
}
