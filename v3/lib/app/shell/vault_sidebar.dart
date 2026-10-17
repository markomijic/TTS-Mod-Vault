import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tts_mod_vault/app/shell/app_destination.dart';
import 'package:tts_mod_vault/app/theme/theme_controller.dart';
import 'package:tts_mod_vault/app/widgets/insets.dart';
import 'package:tts_mod_vault/core/storage/key_value_store.dart';
import 'package:tts_mod_vault/l10n/generated/app_localizations.dart';

/// Whether the sidebar shows labels next to its icons; persisted.
final class SidebarController extends Notifier<bool> {
  /// Store key under which the flag lives.
  static const String storageKey = 'sidebar.extended';

  bool _touched = false;

  @override
  bool build() {
    final store = ref.watch(keyValueStoreProvider);
    _touched = false;
    _restore(store);
    return false;
  }

  Future<void> _restore(KeyValueStore store) async {
    final raw = await store.read(storageKey);
    if (!ref.mounted || _touched || raw == null) return;
    state = raw == 'true';
  }

  /// Sets the extended flag and persists it.
  Future<void> setExtended(bool extended) async {
    _touched = true;
    state = extended;
    await ref.read(keyValueStoreProvider).write(storageKey, '$extended');
  }

  /// Flips between collapsed and extended.
  Future<void> toggle() => setExtended(!state);
}

/// Provides whether the sidebar is extended.
final sidebarExtendedProvider = NotifierProvider<SidebarController, bool>(
  SidebarController.new,
);

/// A sidebar entry that triggers an action rather than navigating.
@immutable
final class SidebarAction {
  /// Creates an action.
  const SidebarAction({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.enabled = true,
  });

  /// Icon shown in both forms.
  final IconData icon;

  /// Label (extended form) and tooltip (collapsed form).
  final String label;

  /// Called when pressed.
  final VoidCallback onPressed;

  /// Whether the item can be pressed.
  final bool enabled;
}

/// The application sidebar.
///
/// A themed column of M3 parts, not a `NavigationRail`, so it can hold
/// actions as well as destinations. It has no hover behaviour: the chevron at
/// the top toggles between the icon-only form ([collapsedWidth]) and the
/// labelled form ([extendedWidth]), and that choice is persisted by
/// [SidebarController].
///
/// Layout, top to bottom: the toggle, the destinations, one divider-separated
/// group per entry of [actionGroups], then [footerActions] pinned to the
/// bottom.
class VaultSidebar extends ConsumerWidget {
  /// Creates the sidebar.
  const VaultSidebar({
    super.key,
    required this.selected,
    required this.onDestinationSelected,
    this.destinationsEnabled = true,
    this.actionGroups = const [],
    this.footerActions = const [],
  });

  /// Width of the icon-only form.
  static const double collapsedWidth = 56;

  /// Width of the labelled form.
  static const double extendedWidth = 232;

  /// Duration of the width animation.
  static const Duration animationDuration = Duration(milliseconds: 200);

  /// The destination to highlight.
  final AppDestination selected;

  /// Called when a destination is pressed.
  final ValueChanged<AppDestination> onDestinationSelected;

  /// Whether the destination items can be pressed.
  final bool destinationsEnabled;

  /// Groups of actions shown under the destinations, separated by dividers.
  final List<List<SidebarAction>> actionGroups;

  /// Actions pinned to the bottom of the sidebar.
  final List<SidebarAction> footerActions;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final extended = ref.watch(sidebarExtendedProvider);
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;

    return AnimatedContainer(
      duration: animationDuration,
      curve: Curves.easeInOut,
      width: extended ? extendedWidth : collapsedWidth,
      color: scheme.surfaceContainerLow,
      padding: const EdgeInsets.symmetric(vertical: Insets.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
            alignment: extended ? Alignment.centerRight : Alignment.center,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: Insets.sm),
              child: IconButton(
                tooltip: extended ? l10n.sidebarCollapse : l10n.sidebarExpand,
                icon: Icon(extended ? Icons.chevron_left : Icons.chevron_right),
                onPressed: () =>
                    ref.read(sidebarExtendedProvider.notifier).toggle(),
              ),
            ),
          ),
          Gaps.h8,
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final destination in AppDestination.values)
                    _SidebarItem(
                      icon: _destinationIcon(destination),
                      label: _destinationLabel(destination, l10n),
                      extended: extended,
                      enabled: destinationsEnabled,
                      selected: destination == selected,
                      onPressed: () => onDestinationSelected(destination),
                    ),
                  for (final group in actionGroups) ...[
                    const _SidebarDivider(),
                    for (final action in group)
                      _SidebarItem.action(action, extended: extended),
                  ],
                ],
              ),
            ),
          ),
          if (footerActions.isNotEmpty) ...[
            const _SidebarDivider(),
            for (final action in footerActions)
              _SidebarItem.action(action, extended: extended),
          ],
        ],
      ),
    );
  }

  static IconData _destinationIcon(AppDestination destination) =>
      switch (destination) {
        AppDestination.mods => Icons.extension_outlined,
        AppDestination.backups => Icons.folder_zip_outlined,
      };

  static String _destinationLabel(
    AppDestination destination,
    AppLocalizations l10n,
  ) => switch (destination) {
    AppDestination.mods => l10n.navMods,
    AppDestination.backups => l10n.navBackups,
  };
}

class _SidebarItem extends StatelessWidget {
  const _SidebarItem({
    required this.icon,
    required this.label,
    required this.extended,
    required this.enabled,
    required this.onPressed,
    this.selected = false,
  });

  _SidebarItem.action(SidebarAction action, {required this.extended})
    : icon = action.icon,
      label = action.label,
      enabled = action.enabled,
      onPressed = action.onPressed,
      selected = false;

  static const double _height = 40;
  static const double _iconSize = 24;

  /// Width of the labelled row: the extended sidebar minus the item's outer
  /// margin and the row's own horizontal padding.
  static const double _extendedContentWidth =
      VaultSidebar.extendedWidth - 4 * Insets.sm;

  final IconData icon;
  final String label;
  final bool extended;
  final bool enabled;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final foreground = !enabled
        ? scheme.onSurface.withValues(alpha: 0.38)
        : selected
        ? scheme.onSecondaryContainer
        : scheme.onSurfaceVariant;
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(_height / 2),
    );

    final iconWidget = Icon(icon, size: _iconSize, color: foreground);

    // While the sidebar animates from collapsed to extended the item is
    // narrower than its final size, so the labelled row is laid out at its
    // final width and clipped; the animation then reveals it.
    final Widget body = extended
        ? ClipRect(
            child: OverflowBox(
              alignment: Alignment.centerLeft,
              minWidth: 0,
              maxWidth: double.infinity,
              child: SizedBox(
                width: _extendedContentWidth,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: Insets.sm),
                  child: Row(
                    children: [
                      iconWidget,
                      Gaps.w12,
                      Expanded(
                        child: Text(
                          label,
                          maxLines: 1,
                          softWrap: false,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelLarge?.copyWith(
                            color: foreground,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          )
        : Center(child: iconWidget);

    Widget item = Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: Insets.sm,
        vertical: Insets.xs / 2,
      ),
      child: Material(
        color: selected ? scheme.secondaryContainer : Colors.transparent,
        shape: shape,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: enabled ? onPressed : null,
          mouseCursor: enabled
              ? SystemMouseCursors.click
              : SystemMouseCursors.basic,
          customBorder: shape,
          child: SizedBox(height: _height, child: body),
        ),
      ),
    );

    if (!extended) {
      item = Tooltip(message: label, child: item);
    }
    return item;
  }
}

class _SidebarDivider extends StatelessWidget {
  const _SidebarDivider();

  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.symmetric(horizontal: Insets.md, vertical: Insets.xs),
    child: Divider(),
  );
}
