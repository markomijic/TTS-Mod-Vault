import 'package:flutter_hooks/flutter_hooks.dart'
    show useState, useTextEditingController, useValueListenable;
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tts_mod_vault/app/widgets/app_dialog.dart';
import 'package:tts_mod_vault/app/widgets/app_snack_bar.dart';
import 'package:tts_mod_vault/app/widgets/insets.dart';
import 'package:tts_mod_vault/core/result/result.dart';
import 'package:tts_mod_vault/domain/models/models.dart';
import 'package:tts_mod_vault/features/asset_detail/presentation/asset_detail_selection.dart';
import 'package:tts_mod_vault/features/library/application/mod_edit_service.dart';
import 'package:tts_mod_vault/features/library/presentation/library_labels.dart';
import 'package:tts_mod_vault/l10n/generated/app_localizations.dart';

/// Width of the dialog body; URLs are long.
const double _dialogWidth = 640;

/// Opens the [ReplaceUrlDialog] for [asset] of [mod].
Future<void> showReplaceUrlDialog(
  BuildContext context, {
  required Mod mod,
  required Asset asset,
}) => showDialog<void>(
  context: context,
  builder: (context) => ReplaceUrlDialog(mod: mod, asset: asset),
);

/// Edits one asset URL inside the mod's JSON (2.x `ReplaceUrlDialog`).
///
/// The field is prefilled with the current URL; Apply is enabled once the
/// trimmed text is non-empty and differs from it. "Also rename the cached
/// file" is only available when the file exists and is on by default then.
/// On success the dialog closes and the URL highlight is cleared; a
/// failure shows its message in a snack bar and keeps the dialog open.
class ReplaceUrlDialog extends HookConsumerWidget {
  /// Creates the dialog.
  const ReplaceUrlDialog({super.key, required this.mod, required this.asset});

  /// The mod whose JSON is edited.
  final Mod mod;

  /// The asset whose URL is replaced.
  final Asset asset;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final controller = useTextEditingController(text: asset.url);
    final value = useValueListenable(controller);
    final renameFile = useState(asset.exists);
    final busy = useState(false);

    final newUrl = value.text.trim();
    final String? validation = newUrl.isEmpty
        ? l10n.replaceUrlEmpty
        : newUrl == asset.url
        ? l10n.replaceUrlUnchanged
        : null;
    final canApply = validation == null && !busy.value;

    Future<void> apply() async {
      busy.value = true;
      final result = await ref
          .read(modEditServiceProvider)
          .replaceAssetUrl(
            mod,
            asset,
            newUrl,
            renameFile: asset.exists && renameFile.value,
          );
      if (!context.mounted) return;
      busy.value = false;
      switch (result) {
        case Ok():
          ref.read(selectedAssetUrlProvider.notifier).clear();
          showAppSnackBar(context, l10n.urlReplaced);
          Navigator.of(context).pop();
        case Err(:final failure):
          showAppSnackBar(context, failure.message);
      }
    }

    return AppDialog(
      title: l10n.replaceUrlTitle,
      content: SizedBox(
        width: _dialogWidth,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.replaceUrlCurrent, style: theme.textTheme.labelLarge),
            Gaps.h4,
            SelectableText(
              asset.url,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            Gaps.h16,
            TextField(
              controller: controller,
              autofocus: true,
              enabled: !busy.value,
              onSubmitted: canApply ? (_) => apply() : null,
              decoration: InputDecoration(
                labelText: l10n.replaceUrlNew,
                border: const OutlineInputBorder(),
                // Do not flag the untouched prefill as "unchanged".
                errorText: value.text == asset.url ? null : validation,
              ),
            ),
            Gaps.h8,
            CheckboxListTile(
              value: asset.exists && renameFile.value,
              onChanged: asset.exists && !busy.value
                  ? (checked) => renameFile.value = checked ?? false
                  : null,
              controlAffinity: ListTileControlAffinity.leading,
              contentPadding: EdgeInsets.zero,
              title: Text(l10n.replaceUrlRenameFile),
            ),
            Gaps.h8,
            Row(
              children: [
                Icon(
                  Icons.warning_amber_rounded,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                Gaps.w8,
                Expanded(
                  child: Text(
                    l10n.replaceUrlWarning(mod.ref.type.singular(l10n)),
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              ],
            ),
            if (busy.value) ...[Gaps.h16, const LinearProgressIndicator()],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: busy.value ? null : () => Navigator.of(context).pop(),
          child: Text(l10n.cancel),
        ),
        FilledButton.icon(
          onPressed: canApply ? apply : null,
          icon: const Icon(Icons.edit_outlined),
          label: Text(l10n.apply),
        ),
      ],
    );
  }
}
