import 'package:meta/meta.dart';

/// Why [StartupNeedsDirectories.error] is set: which of the folders the user
/// handed to `StartupController.continueWithDirectories` failed validation.
enum StartupDirectoriesError {
  /// The Mods folder is neither named `Mods` nor contains a `Mods` folder.
  invalidModsDir,

  /// The Saves folder is neither named `Saves` nor contains a `Saves` folder.
  invalidSavesDir,

  /// Both folders failed validation.
  invalidDirectories,
}

/// Where the app is in its start-up sequence; see `StartupController`.
///
/// ```text
/// Checking -> NeedsDirectories -> (continueWithDirectories) -> Loading
/// Checking -> Loading -> Ready
///             Loading -> Failed -> (retry) -> Checking
/// ```
@immutable
sealed class StartupState {
  const StartupState();
}

/// The stored directories are being read and checked for existence.
final class StartupChecking extends StartupState {
  /// Creates the state.
  const StartupChecking();

  @override
  bool operator ==(Object other) => other is StartupChecking;

  @override
  int get hashCode => (StartupChecking).hashCode;

  @override
  String toString() => 'StartupChecking()';
}

/// The Mods and/or Saves folders do not exist; the user must pick them.
final class StartupNeedsDirectories extends StartupState {
  /// Creates the state.
  const StartupNeedsDirectories({
    required this.modsDirExists,
    required this.savesDirExists,
    this.error,
  });

  /// Whether the currently stored Mods folder exists.
  final bool modsDirExists;

  /// Whether the currently stored Saves folder exists.
  final bool savesDirExists;

  /// Set when the last `continueWithDirectories` call was rejected.
  final StartupDirectoriesError? error;

  @override
  bool operator ==(Object other) =>
      other is StartupNeedsDirectories &&
      other.modsDirExists == modsDirExists &&
      other.savesDirExists == savesDirExists &&
      other.error == error;

  @override
  int get hashCode => Object.hash(modsDirExists, savesDirExists, error);

  @override
  String toString() =>
      'StartupNeedsDirectories(mods: $modsDirExists, saves: $savesDirExists, '
      'error: $error)';
}

/// Folders are valid; the library index is being refreshed.
final class StartupLoading extends StartupState {
  /// Creates the state.
  const StartupLoading();

  @override
  bool operator ==(Object other) => other is StartupLoading;

  @override
  int get hashCode => (StartupLoading).hashCode;

  @override
  String toString() => 'StartupLoading()';
}

/// The library is loaded; the shell can be shown.
final class StartupReady extends StartupState {
  /// Creates the state.
  const StartupReady();

  @override
  bool operator ==(Object other) => other is StartupReady;

  @override
  int get hashCode => (StartupReady).hashCode;

  @override
  String toString() => 'StartupReady()';
}

/// Loading the library threw.
final class StartupFailed extends StartupState {
  /// Creates the state.
  const StartupFailed(this.error, this.stackTrace);

  /// The thrown object.
  final Object error;

  /// Where it was thrown.
  final StackTrace stackTrace;

  @override
  bool operator ==(Object other) =>
      other is StartupFailed &&
      other.error == error &&
      other.stackTrace == stackTrace;

  @override
  int get hashCode => Object.hash(error, stackTrace);

  @override
  String toString() => 'StartupFailed($error)';
}
