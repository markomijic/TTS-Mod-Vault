/// The Update URL presets section of the Settings dialog: the saved
/// label / old prefix / new prefix triples with add, edit and remove.
library;

import 'package:flutter_hooks/flutter_hooks.dart'
    show HookWidget, useState, useTextEditingController;
import 'package:material_ui/material_ui.dart';
import 'package:tts_mod_vault/app/widgets/app_dialog.dart';
import 'package:tts_mod_vault/app/widgets/insets.dart';
import 'package:tts_mod_vault/features/settings/application/app_settings.dart';
import 'package:tts_mod_vault/features/url_updates/application/url_replacement_preset.dart';
import 'package:tts_mod_vault/l10n/generated/app_localizations.dart';

/// Width of the preset editor dialog.
const double _editorWidth = 520;

/// Edits the URL replacement presets of [draft].
class UrlPresetsSection extends StatelessWidget {
  /// Creates the section.
  const UrlPresetsSection({
    super.key,
    required this.draft,
    required this.onChanged,
  });

  /// The settings being edited.
  final AppSettings draft;

  /// Receives the edited settings.
  final ValueChanged<AppSettings> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final presets = draft.urlReplacementPresets;

    void update(List<UrlReplacementPreset> next) =>
        onChanged(draft.copyWith(urlReplacementPresets: next));

    Future<void> edit(int? index) async {
      final result = await showUrlPresetEditor(
        context,
        preset: index == null ? null : presets[index],
      );
      if (result == null) return;
      final next = List<UrlReplacementPreset>.of(presets);
      if (index == null) {
        next.add(result);
      } else {
        next[index] = result;
      }
      update(next);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                l10n.settingsUrlPresetsInfo,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            Gaps.w16,
            FilledButton.tonalIcon(
              onPressed: () => edit(null),
              icon: const Icon(Icons.add),
              label: Text(l10n.settingsAddPreset),
            ),
          ],
        ),
        Gaps.h12,
        Expanded(
          child: presets.isEmpty
              ? Center(
                  child: Text(
                    l10n.settingsNoPresets,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                )
              : ListView.separated(
                  itemCount: presets.length,
                  separatorBuilder: (_, _) => Gaps.h8,
                  itemBuilder: (context, index) => _PresetRow(
                    key: ValueKey('preset-$index'),
                    preset: presets[index],
                    onEdit: () => edit(index),
                    onRemove: () => update(
                      List<UrlReplacementPreset>.of(presets)..removeAt(index),
                    ),
                  ),
                ),
        ),
      ],
    );
  }
}

class _PresetRow extends StatelessWidget {
  const _PresetRow({
    super.key,
    required this.preset,
    required this.onEdit,
    required this.onRemove,
  });

  final UrlReplacementPreset preset;
  final VoidCallback onEdit;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(Insets.sm),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          Insets.md,
          Insets.sm,
          Insets.xs,
          Insets.sm,
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    preset.label,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall,
                  ),
                  Text(
                    l10n.presetOldPrefixValue(preset.oldUrl),
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall,
                  ),
                  Text(
                    l10n.presetNewPrefixValue(preset.newUrl),
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: l10n.edit,
              icon: const Icon(Icons.edit_outlined),
              onPressed: onEdit,
            ),
            IconButton(
              tooltip: l10n.remove,
              icon: const Icon(Icons.delete_outline),
              onPressed: onRemove,
            ),
          ],
        ),
      ),
    );
  }
}

/// Opens the preset editor for [preset] (null: a new one); returns the
/// edited preset or null on Cancel.
Future<UrlReplacementPreset?> showUrlPresetEditor(
  BuildContext context, {
  UrlReplacementPreset? preset,
}) => showDialog<UrlReplacementPreset>(
  context: context,
  builder: (_) => UrlPresetEditorDialog(preset: preset),
);

/// Label / old prefix / new prefix form; every field is required.
class UrlPresetEditorDialog extends HookWidget {
  /// Creates the editor for [preset], or for a new preset when null.
  const UrlPresetEditorDialog({super.key, this.preset});

  /// The preset being edited.
  final UrlReplacementPreset? preset;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final label = useTextEditingController(text: preset?.label ?? '');
    final oldUrl = useTextEditingController(text: preset?.oldUrl ?? '');
    final newUrl = useTextEditingController(text: preset?.newUrl ?? '');
    final showError = useState(false);

    void submit() {
      final result = UrlReplacementPreset(
        label: label.text.trim(),
        oldUrl: oldUrl.text.trim(),
        newUrl: newUrl.text.trim(),
      );
      if (result.label.isEmpty ||
          result.oldUrl.isEmpty ||
          result.newUrl.isEmpty) {
        showError.value = true;
        return;
      }
      Navigator.of(context).pop(result);
    }

    return AppDialog(
      title: preset == null ? l10n.settingsAddPreset : l10n.settingsEditPreset,
      content: SizedBox(
        width: _editorWidth,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              key: const Key('preset-label'),
              controller: label,
              autofocus: true,
              decoration: InputDecoration(
                labelText: l10n.presetLabel,
                border: const OutlineInputBorder(),
              ),
            ),
            Gaps.h12,
            TextField(
              key: const Key('preset-old-url'),
              controller: oldUrl,
              decoration: InputDecoration(
                labelText: l10n.presetOldUrl,
                border: const OutlineInputBorder(),
              ),
            ),
            Gaps.h12,
            TextField(
              key: const Key('preset-new-url'),
              controller: newUrl,
              decoration: InputDecoration(
                labelText: l10n.presetNewUrl,
                border: const OutlineInputBorder(),
              ),
              onSubmitted: (_) => submit(),
            ),
            if (showError.value) ...[
              Gaps.h8,
              Text(
                l10n.presetAllFieldsRequired,
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(color: Theme.of(context).colorScheme.error),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          onPressed: submit,
          child: Text(preset == null ? l10n.add : l10n.save),
        ),
      ],
    );
  }
}
