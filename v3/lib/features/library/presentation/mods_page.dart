import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter_hooks/flutter_hooks.dart' show useFocusNode;
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tts_mod_vault/app/widgets/error_message.dart';
import 'package:tts_mod_vault/app/widgets/insets.dart';
import 'package:tts_mod_vault/app/widgets/progress_message.dart';
import 'package:tts_mod_vault/domain/models/models.dart';
import 'package:tts_mod_vault/features/library/application/library_controller.dart';
import 'package:tts_mod_vault/features/library/application/library_view_providers.dart';
import 'package:tts_mod_vault/features/library/application/refresh_progress.dart';
import 'package:tts_mod_vault/features/library/presentation/library_labels.dart';
import 'package:tts_mod_vault/features/library/presentation/mods_view.dart';
import 'package:tts_mod_vault/features/library/presentation/selected_mod_panel.dart';
import 'package:tts_mod_vault/features/library/presentation/toolbar/bulk_actions_button.dart';
import 'package:tts_mod_vault/features/library/presentation/toolbar/filter_menu_button.dart';
import 'package:tts_mod_vault/features/library/presentation/toolbar/library_help_tooltip.dart';
import 'package:tts_mod_vault/features/library/presentation/toolbar/library_search_field.dart';
import 'package:tts_mod_vault/features/library/presentation/toolbar/mod_type_selector.dart';
import 'package:tts_mod_vault/features/library/presentation/toolbar/sort_menu_button.dart';
import 'package:tts_mod_vault/features/library/presentation/toolbar/view_toggle_button.dart';
import 'package:tts_mod_vault/features/startup/application/directories_controller.dart';
import 'package:tts_mod_vault/l10n/generated/app_localizations.dart';

/// Height of the thin refresh indicator above the toolbar.
const double _refreshBarHeight = 3;

/// The Mods page: toolbar, grid or list, and the selected-mod panel.
///
/// Layout (2.x proportions):
/// ```
/// Row
/// ├─ Expanded(flex: 2) ModsColumn
/// │   ├─ thin LinearProgressIndicator while a refresh runs
/// │   ├─ Wrap toolbar (type selector, search, sort, filters, view toggle,
/// │   │  bulk actions, help)
/// │   ├─ Expanded(ModsView | ProgressMessage | ErrorMessage)
/// │   └─ bottomSlot (log panel and progress bar dock here later)
/// └─ Expanded(flex: 1) SelectedModPanel
/// ```
///
/// Keyboard: Ctrl/Cmd+F focuses the search field; Esc clears the selection,
/// or unfocuses the search field when it has focus.
class ModsPage extends HookConsumerWidget {
  /// Creates the page.
  const ModsPage({super.key, this.bottomSlot = const SizedBox.shrink()});

  /// Docked under the list; the log panel and progress bar go here.
  final Widget bottomSlot;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pageFocus = useFocusNode(debugLabel: 'ModsPage');
    final searchFocus = useFocusNode(debugLabel: 'LibrarySearch');

    void focusSearch() => searchFocus.requestFocus();

    void escape() {
      if (searchFocus.hasFocus) {
        pageFocus.requestFocus();
      } else {
        ref.read(selectionProvider.notifier).clear();
      }
    }

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyF, control: true):
            focusSearch,
        const SingleActivator(LogicalKeyboardKey.keyF, meta: true): focusSearch,
        const SingleActivator(LogicalKeyboardKey.escape): escape,
      },
      child: Focus(
        focusNode: pageFocus,
        autofocus: true,
        child: Row(
          children: [
            Expanded(
              flex: 2,
              child: ModsColumn(
                searchFocusNode: searchFocus,
                bottomSlot: bottomSlot,
              ),
            ),
            const Expanded(child: SelectedModPanel()),
          ],
        ),
      ),
    );
  }
}

/// Toolbar, list and bottom slot of the Mods page.
class ModsColumn extends ConsumerWidget {
  /// Creates the column.
  const ModsColumn({
    super.key,
    required this.searchFocusNode,
    required this.bottomSlot,
  });

  /// Focus node handed to the search field.
  final FocusNode searchFocusNode;

  /// Docked under the list.
  final Widget bottomSlot;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _RefreshBar(),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            Insets.sm,
            Insets.xs,
            Insets.md,
            Insets.sm,
          ),
          child: Wrap(
            spacing: Insets.sm,
            runSpacing: Insets.sm,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              const ModTypeSelector(),
              LibrarySearchField(focusNode: searchFocusNode),
              const SortMenuButton(),
              const FilterMenuButton(),
              const ViewToggleButton(),
              const BulkActionsButton(),
              const LibraryHelpTooltip(),
            ],
          ),
        ),
        const Expanded(
          child: Padding(
            padding: EdgeInsets.only(left: Insets.sm),
            child: _LibraryBody(),
          ),
        ),
        bottomSlot,
      ],
    );
  }
}

/// Thin determinate/indeterminate bar while a refresh runs; keeps its
/// height when idle so the toolbar does not jump.
class _RefreshBar extends ConsumerWidget {
  const _RefreshBar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final loading = ref.watch(
      libraryControllerProvider.select((s) => s.isLoading),
    );
    if (!loading) return const SizedBox(height: _refreshBarHeight);
    final progress = ref.watch(refreshProgressProvider);
    return LinearProgressIndicator(
      minHeight: _refreshBarHeight,
      value: progress?.fraction,
    );
  }
}

/// Picks between the progress message (first load), the error message and
/// the mods view.
class _LibraryBody extends ConsumerWidget {
  const _LibraryBody();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final library = ref.watch(libraryControllerProvider);
    final hasData = library.value?.lastRefresh != null;

    if (library.isLoading && !hasData) {
      return const Center(child: _RefreshProgressMessage());
    }
    if (library.hasError) {
      return Center(
        child: SingleChildScrollView(
          child: ErrorMessage(
            error: library.error!,
            onRetry: () =>
                ref.read(libraryControllerProvider.notifier).refresh(),
          ),
        ),
      );
    }
    return ModsView(emptyHintBuilder: (context) => const _EmptyHint());
  }
}

class _RefreshProgressMessage extends ConsumerWidget {
  const _RefreshProgressMessage();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final progress = ref.watch(refreshProgressProvider);
    if (progress == null) {
      return ProgressMessage(message: l10n.startupLoading);
    }
    final fraction = progress.fraction;
    return ProgressMessage(
      message: progress.phase.label(l10n),
      value: fraction,
      detail: fraction == null
          ? null
          : l10n.progressCount(progress.done, progress.total),
    );
  }
}

/// "No mods match the current filters" or "No mods found in `<folder>`".
class _EmptyHint extends ConsumerWidget {
  const _EmptyHint();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final type = ref.watch(selectedModTypeProvider);
    final filtered = ref.watch(modFilterProvider.select((f) => f.isNotEmpty));
    final plural = type.plural(l10n);

    final String text;
    if (filtered) {
      text = l10n.noModsMatchFilters(plural);
    } else {
      final directories = ref.watch(directoriesProvider).value;
      final folder = switch (type) {
        ModType.mod => directories?.workshopDir,
        ModType.save => directories?.savesDir,
        ModType.savedObject => directories?.savedObjectsDir,
      };
      text = l10n.noModsFound(plural, folder ?? '');
    }

    return Text(
      text,
      textAlign: TextAlign.center,
      style: theme.textTheme.bodyLarge?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
      ),
    );
  }
}
