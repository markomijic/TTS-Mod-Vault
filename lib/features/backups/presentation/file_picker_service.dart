import 'package:file_picker/file_picker.dart'
    show FilePicker, FileType, LinuxOptions, WindowsOptions;
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:tts_mod_vault/domain/constants.dart' show ttsmodExtension;

/// Opens the OS file picker for the files the backup and import flows
/// need. Abstracted so widgets can be tested without `file_picker`
/// (the folder picker has the same shape in
/// `startup/application/directory_picker.dart`).
abstract interface class FilePickerService {
  /// Shows a multi-select picker for `.ttsmod` archives and returns the
  /// chosen paths; empty when the user cancelled.
  Future<List<String>> pickTtsmodFiles({
    String? dialogTitle,
    String? initialDirectory,
  });

  /// Shows a single-file picker for a `.json` file; null when cancelled.
  Future<String?> pickJsonFile({String? dialogTitle, String? initialDirectory});

  /// Shows a single-file picker for a `.png` file; null when cancelled.
  Future<String?> pickPngFile({String? dialogTitle, String? initialDirectory});
}

/// [FilePickerService] backed by `file_picker`'s static API.
final class FilePickerFilePickerService implements FilePickerService {
  /// Creates the service.
  const FilePickerFilePickerService();

  // file_picker 13 moved `lockParentWindow` into the per-platform options.
  static const _windows = WindowsOptions(lockParentWindow: true);
  static const _linux = LinuxOptions(lockParentWindow: true);

  @override
  Future<List<String>> pickTtsmodFiles({
    String? dialogTitle,
    String? initialDirectory,
  }) async {
    final files = await FilePicker.pickFiles(
      dialogTitle: dialogTitle,
      initialDirectory: initialDirectory,
      type: FileType.custom,
      allowedExtensions: [ttsmodExtension.replaceFirst('.', '')],
      windowsOptions: _windows,
      linuxOptions: _linux,
    );
    return [for (final file in files) ?file.path];
  }

  @override
  Future<String?> pickJsonFile({
    String? dialogTitle,
    String? initialDirectory,
  }) => _pickOne(
    dialogTitle: dialogTitle,
    initialDirectory: initialDirectory,
    extension: 'json',
  );

  @override
  Future<String?> pickPngFile({
    String? dialogTitle,
    String? initialDirectory,
  }) => _pickOne(
    dialogTitle: dialogTitle,
    initialDirectory: initialDirectory,
    extension: 'png',
  );

  Future<String?> _pickOne({
    required String extension,
    String? dialogTitle,
    String? initialDirectory,
  }) async {
    final file = await FilePicker.pickFile(
      dialogTitle: dialogTitle,
      initialDirectory: initialDirectory,
      type: FileType.custom,
      allowedExtensions: [extension],
      windowsOptions: _windows,
      linuxOptions: _linux,
    );
    return file?.path;
  }
}

/// The file picker used by the UI; tests override it with a fake.
final filePickerServiceProvider = Provider<FilePickerService>(
  (ref) => const FilePickerFilePickerService(),
);
