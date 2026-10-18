/// "Update URLs" (plan Phase 5): the dialog with presets, `|`-separated
/// old prefixes, one new prefix and the rename option, and the entry point
/// that runs the update for one mod or a bulk target list.
library;

import 'package:flutter_hooks/flutter_hooks.dart'
    show useState, useTextEditingController, useValueListenable;
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;
import 'package:tts_mod_vault/app/theme/vault_colors.dart';
import 'package:tts_mod_vault/app/widgets/app_dialog.dart';
import 'package:tts_mod_vault/app/widgets/insets.dart';
import 'package:tts_mod_vault/domain/models/models.dart';
import 'package:tts_mod_vault/features/bulk/application/bulk_service.dart';
import 'package:tts_mod_vault/features/bulk/presentation/bulk_failures_dialog.dart';
import 'package:tts_mod_vault/features/library/presentation/item_actions.dart';
import 'package:tts_mod_vault/features/library/presentation/library_labels.dart';
import 'package:tts_mod_vault/features/operations/presentation/operation_launcher.dart';
import 'package:tts_mod_vault/features/settings/application/settings_controller.dart'
    show urlReplacementPresetsProvider;
import 'package:tts_mod_vault/features/url_updates/application/url_updates_service.dart';
import 'package:tts_mod_vault/l10n/generated/app_localizations.dart';

/// Width of the dialog body.
const double _dialogWidth = 760;

/// Dropdown value standing for "Custom" (no preset).
const int _customPreset = -1;

/// Separator between old prefixes.
const String _pipe = '|';

/// What the user entered in the [UpdateUrlsDialog].
@immutable
final class UpdateUrlsChoice {
  /// Creates a choice.
  const UpdateUrlsChoice({
    required this.oldPrefixes,
    required this.newPrefix,
    required this.renameFiles,
  });

  /// The prefixes to replace (already split and trimmed).
  final List<String> oldPrefixes;

  /// The replacement prefix.
  final String newPrefix;

  /// Whether cached files are renamed to the new URLs' names.
  final bool renameFiles;
}

/// Opens the [UpdateUrlsDialog] for [mods], then rewrites their URLs: on
/// the `BulkService` when [bulk] (the bulk menu and the multi-select
/// view), otherwise on the `UrlUpdatesService` (the single-mod button).
/// The result is a snack bar ("Updated N mods, renamed M files"), or the
/// [BulkFailuresDialog] when some mods could not be rewritten.
Future<void> updateUrlsWithDialog(
  BuildContext context,
  WidgetRef ref,
  List<Mod> mods, {
  required bool bulk,
}) async {
  if (mods.isEmpty) return;
  final ui = OperationUi.of(context);
  final l10n = ui.l10n;
  final bulkService = ref.read(bulkServiceProvider);
  final urlService = ref.read(urlUpdatesServiceProvider);

  final choice = await showDialog<UpdateUrlsChoice>(
    context: context,
    builder: (_) => UpdateUrlsDialog(mods: mods),
  );
  if (choice == null || !ui.mounted) return;

  final result = await ui.launch(
    () => bulk
        ? bulkService.updateUrls(
            mods,
            oldPrefixes: choice.oldPrefixes,
            newPrefix: choice.newPrefix,
            renameFiles: choice.renameFiles,
          )
        : urlService.updateUrls(
            mods,
            oldPrefixes: choice.oldPrefixes,
            newPrefix: choice.newPrefix,
            renameFiles: choice.renameFiles,
          ),
  );
  if (result == null || !ui.mounted) return;

  var summary = l10n.updateUrlsDone(result.modsUpdated);
  if (result.filesRenamed > 0) {
    summary = l10n.updateUrlsRenamedSuffix(summary, result.filesRenamed);
  }
  if (result.cancelled) {
    summary = l10n.bulkCancelledSuffix(
      summary,
      result.modsProcessed,
      mods.length,
    );
  }
  if (result.failed.isEmpty) {
    ui.showSnackBar(summary);
    return;
  }
  final names = {for (final mod in mods) mod.jsonPath: mod.displayName};
  await ui.showAppDialog<void>(
    (_) => BulkFailuresDialog(
      title: l10n.actionUpdateUrls,
      summary: summary,
      failures: [
        for (final (path, error) in result.failed)
          (name: names[path] ?? p.basename(path), detail: error),
      ],
    ),
  );
}

/// Validation errors of the two prefix fields; null means valid.
typedef UpdateUrlsErrors = ({String? oldError, String? newError});

/// Checks the dialog's input: at least one old prefix, exactly one new
/// prefix (no `|`), and the new prefix differs from every old one.
UpdateUrlsErrors validateUpdateUrls(
  AppLocalizations l10n, {
  required List<String> oldPrefixes,
  required String newPrefix,
}) {
  final String? oldError = oldPrefixes.isEmpty ? l10n.updateUrlsOldEmpty : null;
  final String? newError;
  if (newPrefix.isEmpty) {
    newError = l10n.updateUrlsNewEmpty;
  } else if (newPrefix.contains(_pipe)) {
    newError = l10n.updateUrlsNewSingle;
  } else if (oldPrefixes.contains(newPrefix)) {
    newError = l10n.updateUrlsSameAsOld;
  } else {
    newError = null;
  }
  return (oldError: oldError, newError: newError);
}

/// Port of 2.x `UpdateUrlsDialog`: a preset dropdown ("Custom" plus the
/// presets from Settings), the old prefixes field with the `|` instruction
/// as helper text, the new prefix field, "Rename cached files", a help
/// icon opening the full explanation, the affected count and a warning
/// that JSON files are edited. Apply is enabled only when the input is
/// valid; it pops with an [UpdateUrlsChoice].
class UpdateUrlsDialog extends HookConsumerWidget {
  /// Creates the dialog for [mods].
  const UpdateUrlsDialog({super.key, required this.mods});

  /// The mods that will be updated (one type).
  final List<Mod> mods;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final colors = VaultColors.of(context);
    final presets = ref.watch(urlReplacementPresetsProvider);
    final service = ref.read(urlUpdatesServiceProvider);
    final oldController = useTextEditingController();
    final newController = useTextEditingController();
    final oldText = useValueListenable(oldController).text;
    final newText = useValueListenable(newController).text;
    final renameFiles = useState(true);
    final type = mods.first.ref.type;

    final oldPrefixes = service.parseOldPrefixes(oldText);
    final newPrefix = newText.trim();
    final errors = validateUpdateUrls(
      l10n,
      oldPrefixes: oldPrefixes,
      newPrefix: newPrefix,
    );
    final valid = errors.oldError == null && errors.newError == null;

    // The dropdown shows the preset whose prefixes match the fields, so
    // editing a field falls back to "Custom" without extra state.
    var selectedPreset = _customPreset;
    for (var i = 0; i < presets.length; i++) {
      if (presets[i].oldUrl == oldText && presets[i].newUrl == newText) {
        selectedPreset = i;
        break;
      }
    }

    void applyPreset(int? index) {
      if (index == null || index == _customPreset) return;
      final preset = presets[index];
      oldController.text = preset.oldUrl;
      newController.text = preset.newUrl;
    }

    Future<void> showHelp() => showDialog<void>(
      context: context,
      builder: (context) => AppDialog(
        title: l10n.updateUrlsHelpTooltip,
        content: SizedBox(
          width: _dialogWidth,
          child: SingleChildScrollView(
            child: SelectableText(l10n.updateUrlsHelp),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(l10n.close),
          ),
        ],
      ),
    );

    return AppDialog(
      title: l10n.actionUpdateUrls,
      content: SizedBox(
        width: _dialogWidth,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      l10n.updateUrlsTargets(type.count(l10n, mods.length)),
                    ),
                  ),
                  IconButton(
                    tooltip: l10n.updateUrlsCopyPipe,
                    onPressed: () => copyTextToClipboard(context, _pipe),
                    icon: const Icon(Icons.copy),
                  ),
                  IconButton(
                    tooltip: l10n.updateUrlsHelpTooltip,
                    onPressed: showHelp,
                    icon: const Icon(Icons.help_outline),
                  ),
                ],
              ),
              if (presets.isNotEmpty) ...[
                Gaps.h12,
                InputDecorator(
                  decoration: InputDecoration(
                    labelText: l10n.updateUrlsPreset,
                    border: const OutlineInputBorder(),
                    isDense: true,
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<int>(
                      value: selectedPreset,
                      isExpanded: true,
                      isDense: true,
                      items: [
                        DropdownMenuItem(
                          value: _customPreset,
                          child: Text(l10n.updateUrlsPresetCustom),
                        ),
                        for (var i = 0; i < presets.length; i++)
                          DropdownMenuItem(
                            value: i,
                            child: Text(presets[i].label),
                          ),
                      ],
                      onChanged: applyPreset,
                    ),
                  ),
                ),
              ],
              Gaps.h16,
              TextField(
                controller: oldController,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: l10n.updateUrlsOldLabel,
                  helperText: l10n.updateUrlsInstruction,
                  helperMaxLines: 4,
                  errorText: oldText.trim().isEmpty ? null : errors.oldError,
                  border: const OutlineInputBorder(),
                ),
              ),
              Gaps.h16,
              TextField(
                controller: newController,
                decoration: InputDecoration(
                  labelText: l10n.updateUrlsNewLabel,
                  errorText: newText.trim().isEmpty ? null : errors.newError,
                  border: const OutlineInputBorder(),
                ),
              ),
              Gaps.h8,
              CheckboxListTile(
                value: renameFiles.value,
                onChanged: (value) => renameFiles.value = value ?? false,
                title: Text(l10n.updateUrlsRenameFiles),
                controlAffinity: ListTileControlAffinity.leading,
                contentPadding: EdgeInsets.zero,
                dense: true,
              ),
              Gaps.h8,
              Row(
                children: [
                  Icon(Icons.warning_amber_rounded, color: colors.logWarning),
                  Gaps.w8,
                  Expanded(
                    child: Text(
                      l10n.updateUrlsWarning(type.plural(l10n)),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.cancel),
        ),
        FilledButton.icon(
          onPressed: valid
              ? () => Navigator.of(context).pop(
                  UpdateUrlsChoice(
                    oldPrefixes: oldPrefixes,
                    newPrefix: newPrefix,
                    renameFiles: renameFiles.value,
                  ),
                )
              : null,
          icon: const Icon(Icons.edit_outlined),
          label: Text(l10n.apply),
        ),
      ],
    );
  }
}
