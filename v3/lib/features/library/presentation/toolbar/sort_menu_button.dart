import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tts_mod_vault/domain/models/models.dart';
import 'package:tts_mod_vault/features/library/application/library_view_providers.dart';
import 'package:tts_mod_vault/features/library/presentation/library_labels.dart';
import 'package:tts_mod_vault/l10n/generated/app_localizations.dart';

/// Sort menu: one entry per [ModSortOption] with a check mark on the active
/// one; the button shows the active option's name.
class SortMenuButton extends ConsumerWidget {
  /// Creates the button.
  const SortMenuButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final sort = ref.watch(modFilterProvider.select((f) => f.sort));

    return MenuAnchor(
      builder: (context, controller, _) => OutlinedButton.icon(
        onPressed: controller.isOpen ? controller.close : controller.open,
        icon: const Icon(Icons.sort),
        label: Text(sort.label(l10n)),
      ),
      menuChildren: [
        for (final option in ModSortOption.values)
          MenuItemButton(
            leadingIcon: Icon(option == sort ? Icons.check : null),
            onPressed: () =>
                ref.read(modFilterProvider.notifier).setSort(option),
            child: Text(option.label(l10n)),
          ),
      ],
    );
  }
}
