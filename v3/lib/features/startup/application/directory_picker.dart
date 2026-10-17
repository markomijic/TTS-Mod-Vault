import 'package:file_picker/file_picker.dart'
    show FilePicker, LinuxOptions, WindowsOptions;
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Opens the OS folder picker. Abstracted so widgets can be tested without
/// `file_picker`.
abstract interface class DirectoryPicker {
  /// Shows the picker and returns the chosen directory, or null when the user
  /// cancelled.
  Future<String?> pickDirectory({
    String? dialogTitle,
    String? initialDirectory,
  });
}

/// [DirectoryPicker] backed by `file_picker`'s static API.
final class FilePickerDirectoryPicker implements DirectoryPicker {
  /// Creates the picker.
  const FilePickerDirectoryPicker();

  @override
  Future<String?> pickDirectory({
    String? dialogTitle,
    String? initialDirectory,
  }) => FilePicker.getDirectoryPath(
    dialogTitle: dialogTitle,
    initialDirectory: initialDirectory,
    // file_picker 13 moved `lockParentWindow` into the per-platform options.
    windowsOptions: const WindowsOptions(lockParentWindow: true),
    linuxOptions: const LinuxOptions(lockParentWindow: true),
  );
}

/// The folder picker used by the UI; tests override it with a fake.
final directoryPickerProvider = Provider<DirectoryPicker>(
  (ref) => const FilePickerDirectoryPicker(),
);
