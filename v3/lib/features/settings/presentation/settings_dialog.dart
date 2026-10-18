/// The Settings dialog (plan Phase 5): a section list on the left
/// (Features, Interface, Appearance, Folders, Network, Update URL presets)
/// and the selected section on the right, with Save / Cancel / Reset to
/// defaults.
///
/// Every control edits a local draft `AppSettings` (and a `FolderDraft`);
/// nothing is written until Save, which goes through
/// `SettingsController.update` and then applies the change's consequences:
/// new folders are validated, persisted and followed by a library refresh;
/// a change the index bakes in triggers a refresh; switching saved objects
/// off leaves the Saved Objects tab; a changed default sort is applied to
/// the current filters. The Appearance section is the exception: it edits
/// the theme live for preview and Cancel restores the theme the dialog
/// opened with.
library;

import 'dart:async' show unawaited;

import 'package:flutter_hooks/flutter_hooks.dart' show useMemoized, useState;
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tts_mod_vault/app/providers/app_log_provider.dart';
import 'package:tts_mod_vault/app/theme/theme_controller.dart';
import 'package:tts_mod_vault/app/theme/theme_settings.dart';
import 'package:tts_mod_vault/app/widgets/app_dialog.dart';
import 'package:tts_mod_vault/app/widgets/app_snack_bar.dart';
import 'package:tts_mod_vault/app/widgets/insets.dart';
import 'package:tts_mod_vault/core/logging/app_log.dart';
import 'package:tts_mod_vault/domain/models/directories.dart';
import 'package:tts_mod_vault/features/library/application/backup_view_providers.dart';
import 'package:tts_mod_vault/features/library/application/library_controller.dart';
import 'package:tts_mod_vault/features/library/application/library_tab.dart';
import 'package:tts_mod_vault/features/library/application/library_view_providers.dart';
import 'package:tts_mod_vault/features/settings/application/settings_controller.dart';
import 'package:tts_mod_vault/features/settings/presentation/appearance_section.dart';
import 'package:tts_mod_vault/features/settings/presentation/features_section.dart';
import 'package:tts_mod_vault/features/settings/presentation/folders_section.dart';
import 'package:tts_mod_vault/features/settings/presentation/interface_section.dart';
import 'package:tts_mod_vault/features/settings/presentation/network_section.dart';
import 'package:tts_mod_vault/features/settings/presentation/url_presets_section.dart';
import 'package:tts_mod_vault/features/startup/application/directories_controller.dart';
import 'package:tts_mod_vault/features/startup/application/startup_controller.dart'
    show directoryExistsProvider;
import 'package:tts_mod_vault/l10n/generated/app_localizations.dart';

/// Dialog width.
const double _dialogWidth = 900;

/// Dialog height.
const double _dialogHeight = 600;

/// Width of the section list.
const double _sectionListWidth = 220;

/// Opens the [SettingsDialog]. The barrier does not dismiss it, so Cancel
/// (which restores the theme preview) is the only way out besides Save.
Future<void> showSettingsDialog(BuildContext context) => showDialog<void>(
  context: context,
  barrierDismissible: false,
  builder: (_) => const SettingsDialog(),
);

/// The sections of the dialog, in display order.
enum SettingsSection {
  /// Behaviour switches.
  features,

  /// List / grid, card titles, default sorts, font size.
  interface,

  /// Theme mode, presets, seed colour.
  appearance,

  /// Mods / Saves / Backups folders, excluded subfolders.
  folders,

  /// Concurrency, excluded domains.
  network,

  /// Update URL presets.
  urlPresets;

  /// Localised name.
  String label(AppLocalizations l10n) => switch (this) {
    SettingsSection.features => l10n.settingsSectionFeatures,
    SettingsSection.interface => l10n.settingsSectionInterface,
    SettingsSection.appearance => l10n.settingsSectionAppearance,
    SettingsSection.folders => l10n.settingsSectionFolders,
    SettingsSection.network => l10n.settingsSectionNetwork,
    SettingsSection.urlPresets => l10n.settingsSectionUrlPresets,
  };

  /// Icon in the section list.
  IconData get icon => switch (this) {
    SettingsSection.features => Icons.extension_outlined,
    SettingsSection.interface => Icons.display_settings_outlined,
    SettingsSection.appearance => Icons.palette_outlined,
    SettingsSection.folders => Icons.folder_outlined,
    SettingsSection.network => Icons.cloud_outlined,
    SettingsSection.urlPresets => Icons.link,
  };
}

/// The dialog body. See the library doc.
class SettingsDialog extends HookConsumerWidget {
  /// Creates the dialog, opened on [initialSection].
  const SettingsDialog({
    super.key,
    this.initialSection = SettingsSection.features,
  });

  /// The section shown first.
  final SettingsSection initialSection;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final section = useState(initialSection);
    final draft = useState<AppSettings>(ref.read(settingsProvider));
    final storedDirectories = useMemoized(
      () => ref.read(directoriesProvider).value ?? Directories.empty,
    );
    final folders = useState(
      FolderDraft(
        modsDir: storedDirectories.modsDir,
        savesDir: storedDirectories.savesDir,
        backupsDir: storedDirectories.backupsDir,
      ),
    );
    final originalTheme = useMemoized(() => ref.read(themeControllerProvider));
    final busy = useState(false);

    Future<void> restoreTheme() async {
      if (ref.read(themeControllerProvider) == originalTheme) return;
      await ref.read(themeControllerProvider.notifier).set(originalTheme);
    }

    Future<void> cancel() async {
      await restoreTheme();
      if (context.mounted) Navigator.of(context).pop();
    }

    Future<void> save() async {
      final exists = ref.read(directoryExistsProvider);
      final resolved = resolveFolderDraft(
        folders.value,
        allowCustomSavesFolder: draft.value.allowCustomSavesFolder,
        exists: exists,
      );
      final modsDir = resolved.modsDir;
      final savesDir = resolved.savesDir;
      final backupsDir = resolved.backupsDir;
      if (modsDir == null || savesDir == null || backupsDir == null) {
        section.value = SettingsSection.folders;
        showAppSnackBar(context, l10n.settingsFoldersInvalid);
        return;
      }
      final nextDirectories = Directories(
        modsDir: modsDir,
        savesDir: savesDir,
        backupsDir: backupsDir,
      );
      busy.value = true;
      final previous = ref.read(settingsProvider);
      final effects = await ref
          .read(settingsProvider.notifier)
          .update(draft.value);
      if (!context.mounted) return;
      await _applyEffects(
        ref,
        effects,
        previous: previous,
        next: draft.value,
        directories: nextDirectories,
      );
      if (context.mounted) Navigator.of(context).pop();
    }

    Future<void> reset() async {
      final confirmed = await showConfirmDialog(
        context,
        title: l10n.settingsResetConfirmTitle,
        message: l10n.settingsResetConfirmMessage,
        confirmLabel: l10n.settingsResetToDefaults,
        destructive: true,
      );
      if (!confirmed || !context.mounted) return;
      busy.value = true;
      final previous = ref.read(settingsProvider);
      final effects = await ref.read(settingsProvider.notifier).reset();
      if (!context.mounted) return;
      await ref
          .read(themeControllerProvider.notifier)
          .set(ThemeSettings.defaults());
      if (!context.mounted) return;
      await _applyEffects(
        ref,
        effects,
        previous: previous,
        next: AppSettings.defaults,
        directories: null,
      );
      if (context.mounted) Navigator.of(context).pop();
    }

    final body = switch (section.value) {
      SettingsSection.features => FeaturesSection(
        draft: draft.value,
        onChanged: (next) => draft.value = next,
      ),
      SettingsSection.interface => InterfaceSection(
        draft: draft.value,
        onChanged: (next) => draft.value = next,
      ),
      SettingsSection.appearance => const AppearanceSection(),
      SettingsSection.folders => FoldersSection(
        draft: draft.value,
        onChanged: (next) => draft.value = next,
        folders: folders.value,
        onFoldersChanged: (next) => folders.value = next,
      ),
      SettingsSection.network => NetworkSection(
        draft: draft.value,
        onChanged: (next) => draft.value = next,
      ),
      SettingsSection.urlPresets => UrlPresetsSection(
        draft: draft.value,
        onChanged: (next) => draft.value = next,
      ),
    };

    return Dialog(
      child: SizedBox(
        width: _dialogWidth,
        height: _dialogHeight,
        child: Padding(
          padding: const EdgeInsets.all(Insets.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.only(left: Insets.sm),
                child: Text(
                  l10n.settingsTitle,
                  style: theme.textTheme.headlineSmall,
                ),
              ),
              Gaps.h16,
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(
                      width: _sectionListWidth,
                      child: _SectionList(
                        selected: section.value,
                        onSelected: (next) => section.value = next,
                      ),
                    ),
                    Gaps.w16,
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: Insets.sm,
                        ),
                        child: body,
                      ),
                    ),
                  ],
                ),
              ),
              Gaps.h16,
              Row(
                children: [
                  TextButton.icon(
                    onPressed: busy.value ? null : reset,
                    icon: const Icon(Icons.restart_alt),
                    label: Text(l10n.settingsResetToDefaults),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: busy.value ? null : cancel,
                    child: Text(l10n.cancel),
                  ),
                  Gaps.w8,
                  FilledButton.icon(
                    onPressed: busy.value ? null : save,
                    icon: const Icon(Icons.save_outlined),
                    label: Text(l10n.save),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// What follows a successful save or reset: folders are persisted when
  /// they changed (then the library is refreshed), otherwise a refresh runs
  /// when the effects ask for one; the Saved Objects tab is left when it
  /// disappeared; changed default sorts are applied. [directories] is null
  /// when the folders were not edited (reset).
  static Future<void> _applyEffects(
    WidgetRef ref,
    SettingsChangeEffects effects, {
    required AppSettings previous,
    required AppSettings next,
    required Directories? directories,
  }) async {
    final stored = ref.read(directoriesProvider).value;
    final foldersChanged = directories != null && directories != stored;
    if (foldersChanged) {
      await ref.read(directoriesProvider.notifier).set(directories);
      _refreshLibrary(ref);
    } else if (effects.needsLibraryRefresh) {
      _refreshLibrary(ref);
    }
    if (effects.hidesSavedObjects &&
        ref.read(libraryTabProvider) == LibraryTab.savedObjects) {
      ref.read(libraryTabProvider.notifier).set(LibraryTab.mods);
    }
    if (previous.defaultSortOption != next.defaultSortOption) {
      ref.read(modFilterProvider.notifier).setSort(next.defaultSortOption);
    }
    if (previous.defaultBackupSortOption != next.defaultBackupSortOption) {
      ref
          .read(backupFilterProvider.notifier)
          .setSort(next.defaultBackupSortOption);
    }
  }

  /// Starts a library refresh without waiting for it; a failure is logged
  /// (the library provider reports it to the page as well).
  static void _refreshLibrary(WidgetRef ref) {
    final log = ref.read(appLogProvider);
    unawaited(
      Future<void>.sync(ref.read(libraryControllerProvider.notifier).refresh)
          .catchError((Object error, StackTrace stackTrace) {
            log.error(
              LogSource.settings,
              'Library refresh after a settings change failed',
              error: error,
              stackTrace: stackTrace,
            );
          }),
    );
  }
}

class _SectionList extends StatelessWidget {
  const _SectionList({required this.selected, required this.onSelected});

  final SettingsSection selected;
  final ValueChanged<SettingsSection> onSelected;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    return ListView(
      children: [
        for (final section in SettingsSection.values)
          ListTile(
            leading: Icon(section.icon),
            title: Text(section.label(l10n)),
            selected: section == selected,
            selectedTileColor: scheme.secondaryContainer,
            selectedColor: scheme.onSecondaryContainer,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(Insets.sm),
            ),
            onTap: () => onSelected(section),
          ),
      ],
    );
  }
}
