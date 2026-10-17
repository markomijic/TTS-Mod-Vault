import 'package:flutter_hooks/flutter_hooks.dart' show useState;
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tts_mod_vault/app/widgets/app_dialog.dart';
import 'package:tts_mod_vault/app/widgets/insets.dart';
import 'package:tts_mod_vault/domain/models/models.dart';
import 'package:tts_mod_vault/features/cleanup/application/delete_assets_service.dart';
import 'package:tts_mod_vault/features/library/presentation/library_labels.dart';
import 'package:tts_mod_vault/features/operations/presentation/operation_launcher.dart';
import 'package:tts_mod_vault/l10n/generated/app_localizations.dart';

/// Width of the dialog body.
const double _dialogWidth = 640;

/// Height cap of the shared-files list inside the dialog.
const double _sharedListMaxHeight = 280;

/// Bottom bar "Delete assets": scans the cached files of [mod], shows the
/// [DeleteModAssetsDialog] (exclusive count, shared files with the mods
/// that use them, "also delete shared files"), then deletes the chosen
/// scope on the runner and reports with a snack bar. A mod without cached
/// files gets an informational snack bar instead.
Future<void> deleteModAssetsWithDialog(
  BuildContext context,
  WidgetRef ref,
  Mod mod,
) async {
  final ui = OperationUi.of(context);
  final l10n = ui.l10n;
  final service = ref.read(deleteAssetsServiceProvider);

  final scan = await service.scanModAssets(mod);
  if (!ui.mounted) return;
  if (scan.isEmpty) {
    ui.showSnackBar(l10n.deleteAssetsNothing);
    return;
  }
  final includeShared = await ui.showAppDialog<bool>(
    (_) => DeleteModAssetsDialog(mod: mod, scan: scan),
  );
  if (includeShared == null) return;

  final scope = includeShared
      ? DeleteAssetsScope.all
      : DeleteAssetsScope.exclusiveOnly;
  final result = await ui.launch(
    () => service.deleteModAssets(mod, scope: scope, scan: scan),
  );
  if (result == null) return;
  final summary = l10n.deleteAssetsDone(result.deleted);
  ui.showSnackBar(
    result.failed == 0
        ? summary
        : l10n.deleteFailedSuffix(summary, result.failed),
  );
}

/// Port of 2.x's single-mod delete dialog: how many files only this mod
/// uses, an expandable list of the shared URLs grouped by asset type with
/// the mods sharing each, and a checkbox to delete the shared files too.
/// Pops with the checkbox value on Delete, null on Cancel. Delete is
/// disabled when the chosen scope covers no file.
class DeleteModAssetsDialog extends HookConsumerWidget {
  /// Creates the dialog for [mod] and its [scan].
  const DeleteModAssetsDialog({
    super.key,
    required this.mod,
    required this.scan,
  });

  /// The mod whose files are deleted.
  final Mod mod;

  /// The scan the dialog shows and the delete reuses.
  final DeletableAssetsScan scan;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final includeShared = useState(false);
    final type = mod.ref.type.singular(l10n);
    final shared = scan.shared;
    final canDelete = scan.exclusive.isNotEmpty || includeShared.value;

    return AppDialog(
      title: l10n.deleteAssetsTitle(mod.displayName),
      content: SizedBox(
        width: _dialogWidth,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.deleteAssetsExclusive(scan.exclusive.length, type)),
            if (shared.isNotEmpty) ...[
              Gaps.h8,
              Text(l10n.deleteAssetsShared(shared.length)),
              Gaps.h8,
              ExpansionTile(
                title: Text(l10n.deleteAssetsSharedList(shared.length)),
                tilePadding: EdgeInsets.zero,
                childrenPadding: const EdgeInsets.only(bottom: Insets.sm),
                children: [
                  ConstrainedBox(
                    constraints: const BoxConstraints(
                      maxHeight: _sharedListMaxHeight,
                    ),
                    child: _SharedAssetsList(scan: scan),
                  ),
                ],
              ),
              CheckboxListTile(
                value: includeShared.value,
                onChanged: (value) => includeShared.value = value ?? false,
                title: Text(l10n.deleteAssetsIncludeShared(shared.length)),
                controlAffinity: ListTileControlAffinity.leading,
                contentPadding: EdgeInsets.zero,
                visualDensity: VisualDensity.compact,
              ),
            ],
            Gaps.h16,
            Text(
              l10n.deleteAssetsNote(type),
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.cancel),
        ),
        FilledButton.icon(
          onPressed: canDelete
              ? () => Navigator.of(context).pop(includeShared.value)
              : null,
          style: FilledButton.styleFrom(
            backgroundColor: scheme.error,
            foregroundColor: scheme.onError,
            disabledBackgroundColor: scheme.onSurface.withValues(alpha: 0.12),
            disabledForegroundColor: scheme.onSurface.withValues(alpha: 0.38),
          ),
          icon: const Icon(Icons.delete_outline),
          label: Text(l10n.menuDelete),
        ),
      ],
    );
  }
}

/// "Alpha, Beta (mods); My Save (saves)" for one shared URL.
String sharedWithText(
  AppLocalizations l10n,
  Map<ModType, List<String>> byType,
) => [
  for (final type in ModType.values)
    if (byType[type] case final names? when names.isNotEmpty)
      l10n.deleteAssetsSharedGroup(
        names.join(l10n.listSeparator),
        type.plural(l10n),
      ),
].join('; ');

/// The shared assets grouped by type, each with the mods sharing it.
class _SharedAssetsList extends StatelessWidget {
  const _SharedAssetsList({required this.scan});

  final DeletableAssetsScan scan;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final groups = <AssetType, List<Asset>>{};
    for (final asset in scan.shared) {
      groups.putIfAbsent(asset.type, () => []).add(asset);
    }
    final rows = <Widget>[];
    for (final type in AssetType.values) {
      final assets = groups[type];
      if (assets == null) continue;
      rows.add(
        Padding(
          padding: const EdgeInsets.only(top: Insets.sm, bottom: Insets.xs),
          child: Text(
            type.label(l10n),
            style: theme.textTheme.titleSmall?.copyWith(
              color: theme.colorScheme.primary,
            ),
          ),
        ),
      );
      for (final asset in assets) {
        final byType = scan.sharedDetails[asset.url];
        rows.add(
          Padding(
            padding: const EdgeInsets.symmetric(vertical: Insets.xs),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SelectableText(asset.url, style: theme.textTheme.bodyMedium),
                if (byType != null && byType.isNotEmpty)
                  Text(
                    l10n.deleteAssetsSharedWith(sharedWithText(l10n, byType)),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
        );
      }
    }
    return ListView(shrinkWrap: true, children: rows);
  }
}
