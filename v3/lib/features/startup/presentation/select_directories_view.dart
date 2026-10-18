import 'package:flutter_hooks/flutter_hooks.dart'
    show useState, useTextEditingController;
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;
import 'package:tts_mod_vault/app/theme/vault_colors.dart';
import 'package:tts_mod_vault/app/widgets/app_snack_bar.dart';
import 'package:tts_mod_vault/app/widgets/insets.dart';
import 'package:tts_mod_vault/domain/models/directories.dart';
import 'package:tts_mod_vault/domain/rules/tts_paths.dart';
import 'package:tts_mod_vault/features/settings/application/settings_controller.dart';
import 'package:tts_mod_vault/features/startup/application/directories_controller.dart';
import 'package:tts_mod_vault/features/startup/application/directory_picker.dart';
import 'package:tts_mod_vault/features/startup/application/startup_controller.dart';
import 'package:tts_mod_vault/l10n/generated/app_localizations.dart';

/// Widest the form gets on large windows.
const double _maxWidth = 600;

/// Lets the user locate the Mods and Saves folders (and optionally a backups
/// folder) when the stored ones do not exist. Port of 2.x
/// `SelectDirectoriesWidget`.
///
/// Paths can be typed or picked with Browse. A path is accepted when it is
/// the `Mods`/`Saves` folder itself or a folder containing it (the TTS data
/// folder), so "Select Tabletop Simulator folder" fills both fields with one
/// pick. Continue is enabled only when both resolve; it hands the raw paths
/// to `StartupController.continueWithDirectories`, which resolves and
/// persists them.
class SelectDirectoriesView extends HookConsumerWidget {
  /// Creates the view for [state].
  const SelectDirectoriesView({super.key, required this.state});

  /// The controller state this view renders.
  final StartupNeedsDirectories state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final exists = ref.watch(directoryExistsProvider);
    final allowCustomSaves = ref.watch(allowCustomSavesFolderSettingProvider);
    final stored =
        ref.watch(directoriesProvider).value ??
        defaultDirectories(
          platform: ref.watch(platformNameProvider),
          home: ref.watch(userHomeProvider),
          directoryExists: exists,
        );

    final modsController = useTextEditingController(text: stored.modsDir);
    final savesController = useTextEditingController(text: stored.savesDir);
    final backupsController = useTextEditingController(text: stored.backupsDir);
    // Mirrors of the controllers' text so edits trigger a rebuild.
    final modsPath = useState(stored.modsDir);
    final savesPath = useState(stored.savesDir);
    final backupsPath = useState(stored.backupsDir);

    final resolvedMods = resolveModsDir(
      modsPath.value,
      directoryExists: exists,
    );
    final resolvedSaves = resolveSavesDir(
      savesPath.value,
      allowCustomPath: allowCustomSaves,
      directoryExists: exists,
    );
    final backupsOk =
        backupsPath.value.isEmpty || exists(p.normalize(backupsPath.value));
    final canContinue =
        resolvedMods != null && resolvedSaves != null && backupsOk;

    Future<void> browse({
      required String title,
      required String current,
      required void Function(String path) onPicked,
    }) async {
      final String? picked;
      try {
        picked = await ref
            .read(directoryPickerProvider)
            .pickDirectory(
              dialogTitle: title,
              initialDirectory: _nearestExisting(current, exists),
            );
      } on Object catch (_) {
        if (context.mounted) showAppSnackBar(context, l10n.filePickerFailed);
        return;
      }
      if (picked != null) onPicked(picked);
    }

    void setPath(
      TextEditingController controller,
      ValueNotifier<String> mirror,
      String path,
    ) {
      controller.text = path;
      mirror.value = path;
    }

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(Insets.xl),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: _maxWidth),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                l10n.selectDirectoriesTitle,
                textAlign: TextAlign.center,
                style: theme.textTheme.titleLarge,
              ),
              Gaps.h8,
              Text(
                l10n.selectDirectoriesHint,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              if (state.error case final error?) ...[
                Gaps.h16,
                _ErrorBanner(message: _errorText(l10n, error)),
              ],
              Gaps.h24,
              Align(
                child: OutlinedButton.icon(
                  onPressed: () => browse(
                    title: l10n.selectTtsFolder,
                    current: modsPath.value,
                    onPicked: (path) {
                      setPath(modsController, modsPath, path);
                      setPath(savesController, savesPath, path);
                    },
                  ),
                  icon: const Icon(Icons.folder_open_outlined),
                  label: Text(l10n.selectTtsFolder),
                ),
              ),
              Gaps.h24,
              _FolderField(
                label: l10n.modsFolderLabel,
                controller: modsController,
                onChanged: (value) => modsPath.value = value,
                onBrowse: () => browse(
                  title: l10n.modsFolderLabel,
                  current: modsPath.value,
                  onPicked: (path) => setPath(modsController, modsPath, path),
                ),
                status: _status(
                  l10n,
                  path: modsPath.value,
                  resolved: resolvedMods,
                  invalidMessage: l10n.modsFolderInvalid,
                  exists: exists,
                ),
              ),
              Gaps.h16,
              _FolderField(
                label: l10n.savesFolderLabel,
                controller: savesController,
                onChanged: (value) => savesPath.value = value,
                onBrowse: () => browse(
                  title: l10n.savesFolderLabel,
                  current: savesPath.value,
                  onPicked: (path) => setPath(savesController, savesPath, path),
                ),
                status: _status(
                  l10n,
                  path: savesPath.value,
                  resolved: resolvedSaves,
                  invalidMessage: allowCustomSaves
                      ? l10n.folderNotFound
                      : l10n.savesFolderInvalid,
                  exists: exists,
                ),
              ),
              Gaps.h16,
              _FolderField(
                label: l10n.backupsFolderLabel,
                controller: backupsController,
                onChanged: (value) => backupsPath.value = value,
                onBrowse: () => browse(
                  title: l10n.backupsFolderLabel,
                  current: backupsPath.value,
                  onPicked: (path) =>
                      setPath(backupsController, backupsPath, path),
                ),
                status: backupsPath.value.isEmpty
                    ? _FolderStatus.neutral(l10n.folderNotSet)
                    : backupsOk
                    ? _FolderStatus.ok(
                        l10n.folderFound(p.normalize(backupsPath.value)),
                      )
                    : _FolderStatus.error(l10n.folderNotFound),
              ),
              Gaps.h24,
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton.icon(
                  onPressed: canContinue
                      ? () => ref
                            .read(startupControllerProvider.notifier)
                            .continueWithDirectories(
                              Directories(
                                modsDir: modsPath.value,
                                savesDir: savesPath.value,
                                backupsDir: backupsPath.value.isEmpty
                                    ? ''
                                    : p.normalize(backupsPath.value),
                              ),
                            )
                      : null,
                  icon: const Icon(Icons.arrow_forward),
                  label: Text(l10n.continueAction),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static _FolderStatus _status(
    AppLocalizations l10n, {
    required String path,
    required String? resolved,
    required String invalidMessage,
    required DirectoryExists exists,
  }) {
    if (resolved != null) return _FolderStatus.ok(l10n.folderFound(resolved));
    if (path.trim().isEmpty) return _FolderStatus.neutral(l10n.folderNotSet);
    if (!exists(p.normalize(path))) {
      return _FolderStatus.error(l10n.folderNotFound);
    }
    return _FolderStatus.error(invalidMessage);
  }

  static String _errorText(
    AppLocalizations l10n,
    StartupDirectoriesError error,
  ) => switch (error) {
    StartupDirectoriesError.invalidModsDir => l10n.errorInvalidModsDir,
    StartupDirectoriesError.invalidSavesDir => l10n.errorInvalidSavesDir,
    StartupDirectoriesError.invalidDirectories => l10n.errorInvalidDirectories,
  };

  /// [path] itself when it exists, otherwise its closest existing ancestor;
  /// null when nothing on the way to the root exists.
  static String? _nearestExisting(String path, DirectoryExists exists) {
    if (path.trim().isEmpty) return null;
    var current = p.normalize(path);
    while (true) {
      if (exists(current)) return current;
      final parent = p.dirname(current);
      if (parent == current) return null;
      current = parent;
    }
  }
}

enum _StatusKind { neutral, ok, error }

@immutable
final class _FolderStatus {
  const _FolderStatus.neutral(this.message) : kind = _StatusKind.neutral;
  const _FolderStatus.ok(this.message) : kind = _StatusKind.ok;
  const _FolderStatus.error(this.message) : kind = _StatusKind.error;

  final _StatusKind kind;
  final String message;
}

class _FolderField extends StatelessWidget {
  const _FolderField({
    required this.label,
    required this.controller,
    required this.onChanged,
    required this.onBrowse,
    required this.status,
  });

  final String label;
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final VoidCallback onBrowse;
  final _FolderStatus status;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final vault = VaultColors.of(context);
    final l10n = AppLocalizations.of(context);

    final (statusColor, statusIcon) = switch (status.kind) {
      _StatusKind.neutral => (scheme.onSurfaceVariant, Icons.remove),
      _StatusKind.ok => (vault.assetPresent, Icons.check_circle_outline),
      _StatusKind.error => (scheme.error, Icons.error_outline),
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                onChanged: onChanged,
                decoration: InputDecoration(
                  labelText: label,
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ),
            Gaps.w8,
            OutlinedButton.icon(
              onPressed: onBrowse,
              icon: const Icon(Icons.folder_open_outlined),
              label: Text(l10n.browse),
            ),
          ],
        ),
        Gaps.h4,
        Padding(
          padding: const EdgeInsets.only(left: Insets.md),
          child: Row(
            children: [
              Icon(statusIcon, size: Insets.lg, color: statusColor),
              Gaps.w4,
              Expanded(
                child: Text(
                  status.message,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: statusColor,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.errorContainer,
        borderRadius: BorderRadius.circular(Insets.sm),
      ),
      child: Padding(
        padding: const EdgeInsets.all(Insets.md),
        child: Row(
          children: [
            Icon(Icons.error_outline, color: scheme.onErrorContainer),
            Gaps.w8,
            Expanded(
              child: Text(
                message,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: scheme.onErrorContainer,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
