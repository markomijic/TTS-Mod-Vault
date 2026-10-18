/// The Folders section of the Settings dialog: Mods, Saves and Backups
/// paths with Browse and the same validation as the start-up folder
/// picker, plus the excluded subfolders list.
library;

import 'package:flutter_hooks/flutter_hooks.dart' show useTextEditingController;
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;
import 'package:tts_mod_vault/app/theme/vault_colors.dart';
import 'package:tts_mod_vault/app/widgets/app_snack_bar.dart';
import 'package:tts_mod_vault/app/widgets/insets.dart';
import 'package:tts_mod_vault/domain/rules/tts_paths.dart';
import 'package:tts_mod_vault/features/settings/application/app_settings.dart';
import 'package:tts_mod_vault/features/settings/presentation/editable_string_list.dart';
import 'package:tts_mod_vault/features/settings/presentation/settings_widgets.dart';
import 'package:tts_mod_vault/features/startup/application/directory_picker.dart';
import 'package:tts_mod_vault/features/startup/application/startup_controller.dart'
    show directoryExistsProvider;
import 'package:tts_mod_vault/l10n/generated/app_localizations.dart';

/// The folder paths being edited in the dialog (raw text; resolved on
/// save with `resolveModsDir` / `resolveSavesDir`).
@immutable
final class FolderDraft {
  /// Creates a draft.
  const FolderDraft({
    required this.modsDir,
    required this.savesDir,
    required this.backupsDir,
  });

  /// Mods folder text.
  final String modsDir;

  /// Saves folder text.
  final String savesDir;

  /// Backups folder text; empty when none.
  final String backupsDir;

  /// Copy with some fields replaced.
  FolderDraft copyWith({
    String? modsDir,
    String? savesDir,
    String? backupsDir,
  }) => FolderDraft(
    modsDir: modsDir ?? this.modsDir,
    savesDir: savesDir ?? this.savesDir,
    backupsDir: backupsDir ?? this.backupsDir,
  );

  @override
  bool operator ==(Object other) =>
      other is FolderDraft &&
      other.modsDir == modsDir &&
      other.savesDir == savesDir &&
      other.backupsDir == backupsDir;

  @override
  int get hashCode => Object.hash(modsDir, savesDir, backupsDir);
}

/// The resolved folders of a [FolderDraft]: null fields are invalid.
typedef ResolvedFolders = ({
  String? modsDir,
  String? savesDir,
  String? backupsDir,
});

/// Resolves [draft] the way the start-up picker does: the Mods and Saves
/// paths may be the folders themselves or a parent containing them; the
/// backups path must exist or be empty (which becomes '').
ResolvedFolders resolveFolderDraft(
  FolderDraft draft, {
  required bool allowCustomSavesFolder,
  required DirectoryExists exists,
}) {
  final backups = draft.backupsDir.trim();
  return (
    modsDir: resolveModsDir(draft.modsDir, directoryExists: exists),
    savesDir: resolveSavesDir(
      draft.savesDir,
      allowCustomPath: allowCustomSavesFolder,
      directoryExists: exists,
    ),
    backupsDir: backups.isEmpty
        ? ''
        : exists(p.normalize(backups))
        ? p.normalize(backups)
        : null,
  );
}

/// Edits the folder paths in [folders] and the excluded subfolders of
/// [draft].
class FoldersSection extends HookConsumerWidget {
  /// Creates the section.
  const FoldersSection({
    super.key,
    required this.draft,
    required this.onChanged,
    required this.folders,
    required this.onFoldersChanged,
  });

  /// The settings being edited (for the excluded subfolders and the custom
  /// Saves folder switch).
  final AppSettings draft;

  /// Receives the edited settings.
  final ValueChanged<AppSettings> onChanged;

  /// The folder paths being edited.
  final FolderDraft folders;

  /// Receives the edited folder paths.
  final ValueChanged<FolderDraft> onFoldersChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final exists = ref.watch(directoryExistsProvider);
    final modsController = useTextEditingController(text: folders.modsDir);
    final savesController = useTextEditingController(text: folders.savesDir);
    final backupsController = useTextEditingController(
      text: folders.backupsDir,
    );
    final resolved = resolveFolderDraft(
      folders,
      allowCustomSavesFolder: draft.allowCustomSavesFolder,
      exists: exists,
    );

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
              initialDirectory: nearestExistingDirectory(current, exists),
            );
      } on Object catch (_) {
        if (context.mounted) showAppSnackBar(context, l10n.filePickerFailed);
        return;
      }
      if (picked != null) onPicked(picked);
    }

    void setMods(String path) {
      modsController.text = path;
      onFoldersChanged(folders.copyWith(modsDir: path));
    }

    void setSaves(String path) {
      savesController.text = path;
      onFoldersChanged(folders.copyWith(savesDir: path));
    }

    void setBackups(String path) {
      backupsController.text = path;
      onFoldersChanged(folders.copyWith(backupsDir: path));
    }

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SettingsSectionTitle(
            l10n.modsFolderLabel,
            info: l10n.settingsFoldersInfo,
          ),
          SettingsFolderField(
            key: const Key('settings-mods-folder'),
            controller: modsController,
            onChanged: (value) =>
                onFoldersChanged(folders.copyWith(modsDir: value)),
            onBrowse: () => browse(
              title: l10n.modsFolderLabel,
              current: folders.modsDir,
              onPicked: setMods,
            ),
            status: folderStatus(
              l10n,
              path: folders.modsDir,
              resolved: resolved.modsDir,
              invalidMessage: l10n.modsFolderInvalid,
              exists: exists,
            ),
          ),
          Gaps.h16,
          SettingsSectionTitle(
            l10n.savesFolderLabel,
            info: l10n.settingsFoldersInfo,
          ),
          SettingsFolderField(
            key: const Key('settings-saves-folder'),
            controller: savesController,
            onChanged: (value) =>
                onFoldersChanged(folders.copyWith(savesDir: value)),
            onBrowse: () => browse(
              title: l10n.savesFolderLabel,
              current: folders.savesDir,
              onPicked: setSaves,
            ),
            status: folderStatus(
              l10n,
              path: folders.savesDir,
              resolved: resolved.savesDir,
              invalidMessage: draft.allowCustomSavesFolder
                  ? l10n.folderNotFound
                  : l10n.savesFolderInvalid,
              exists: exists,
            ),
          ),
          Gaps.h16,
          SettingsSectionTitle(
            l10n.backupsFolderLabel,
            info: l10n.settingBackupsFolderInfo,
          ),
          SettingsFolderField(
            key: const Key('settings-backups-folder'),
            controller: backupsController,
            onChanged: (value) =>
                onFoldersChanged(folders.copyWith(backupsDir: value)),
            onBrowse: () => browse(
              title: l10n.backupsFolderLabel,
              current: folders.backupsDir,
              onPicked: setBackups,
            ),
            onClear: folders.backupsDir.isEmpty ? null : () => setBackups(''),
            status: folders.backupsDir.trim().isEmpty
                ? FolderStatus.neutral(l10n.folderNotSet)
                : resolved.backupsDir != null
                ? FolderStatus.ok(l10n.folderFound(resolved.backupsDir!))
                : FolderStatus.error(l10n.folderNotFound),
          ),
          Gaps.h24,
          EditableStringList(
            title: l10n.settingIgnoredSubfolders,
            info: l10n.settingIgnoredSubfoldersInfo,
            values: draft.ignoredSubfolders,
            addLabel: l10n.settingAddSubfolder,
            onChanged: (list) =>
                onChanged(draft.copyWith(ignoredSubfolders: list)),
          ),
        ],
      ),
    );
  }
}

/// The status line under a folder field.
FolderStatus folderStatus(
  AppLocalizations l10n, {
  required String path,
  required String? resolved,
  required String invalidMessage,
  required DirectoryExists exists,
}) {
  if (resolved != null) return FolderStatus.ok(l10n.folderFound(resolved));
  if (path.trim().isEmpty) return FolderStatus.neutral(l10n.folderNotSet);
  if (!exists(p.normalize(path))) {
    return FolderStatus.error(l10n.folderNotFound);
  }
  return FolderStatus.error(invalidMessage);
}

/// [path] itself when it exists, otherwise its closest existing ancestor;
/// null when nothing on the way to the root exists.
String? nearestExistingDirectory(String path, DirectoryExists exists) {
  if (path.trim().isEmpty) return null;
  var current = p.normalize(path);
  while (true) {
    if (exists(current)) return current;
    final parent = p.dirname(current);
    if (parent == current) return null;
    current = parent;
  }
}

/// How a folder field's status line is drawn.
enum FolderStatusKind {
  /// Nothing to say (empty optional field).
  neutral,

  /// The folder resolves.
  ok,

  /// The folder is missing or invalid.
  error,
}

/// A folder field's status line.
@immutable
final class FolderStatus {
  /// A neutral status.
  const FolderStatus.neutral(this.message) : kind = FolderStatusKind.neutral;

  /// A success status.
  const FolderStatus.ok(this.message) : kind = FolderStatusKind.ok;

  /// An error status.
  const FolderStatus.error(this.message) : kind = FolderStatusKind.error;

  /// How the line is drawn.
  final FolderStatusKind kind;

  /// The text.
  final String message;
}

/// A path text field with Browse (and an optional Clear) and a status
/// line under it.
class SettingsFolderField extends StatelessWidget {
  /// Creates the field.
  const SettingsFolderField({
    super.key,
    required this.controller,
    required this.onChanged,
    required this.onBrowse,
    required this.status,
    this.onClear,
  });

  /// Holds the path text.
  final TextEditingController controller;

  /// Called on every edit.
  final ValueChanged<String> onChanged;

  /// Opens the folder picker.
  final VoidCallback onBrowse;

  /// Clears the field; null hides the button.
  final VoidCallback? onClear;

  /// The status line.
  final FolderStatus status;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final vault = VaultColors.of(context);
    final l10n = AppLocalizations.of(context);

    final (statusColor, statusIcon) = switch (status.kind) {
      FolderStatusKind.neutral => (scheme.onSurfaceVariant, Icons.remove),
      FolderStatusKind.ok => (vault.assetPresent, Icons.check_circle_outline),
      FolderStatusKind.error => (scheme.error, Icons.error_outline),
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
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
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
            if (onClear case final onClear?) ...[
              Gaps.w8,
              OutlinedButton.icon(
                onPressed: onClear,
                icon: const Icon(Icons.clear),
                label: Text(l10n.clear),
              ),
            ],
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
