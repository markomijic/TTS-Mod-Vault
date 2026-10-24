import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tts_mod_vault/app/providers/infrastructure_providers.dart';
import 'package:tts_mod_vault/app/theme/app_theme.dart';
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
/// Styled as an Apple source list: a grey panel with a hairline edge,
/// accent-coloured icons and rounded hover rows. It is not a
/// `NavigationRail`: it holds actions
/// only (there is one library page, with the type selector carrying the
/// Mods / Saves / Saved Objects / Backups tabs), so nothing in it is ever
/// highlighted. It has no hover behaviour: the sidebar button at the top toggles
/// between the icon-only form ([collapsedWidth]) and the labelled form
/// ([extendedWidth]), and that choice is persisted by [SidebarController].
///
/// Layout, top to bottom: the toggle, one divider-separated group per entry
/// of [actionGroups], then [footerActions] pinned to the bottom.
class VaultSidebar extends ConsumerWidget {
  /// Creates the sidebar.
  const VaultSidebar({
    super.key,
    this.actionGroups = const [],
    this.footerActions = const [],
  });

  /// Width of the icon-only form.
  static const double collapsedWidth = 56;

  /// Width of the labelled form.
  static const double extendedWidth = 232;

  /// Duration of the width animation.
  static const Duration animationDuration = Duration(milliseconds: 200);

  /// Groups of actions, separated by dividers.
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
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        border: Border(right: BorderSide(color: scheme.outlineVariant)),
      ),
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
                icon: const Icon(Icons.view_sidebar_outlined),
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
                  for (final (index, group) in actionGroups.indexed) ...[
                    if (index > 0) const _SidebarDivider(),
                    for (final action in group)
                      _SidebarItem(action, extended: extended),
                  ],
                ],
              ),
            ),
          ),
          if (footerActions.isNotEmpty) ...[
            const _SidebarDivider(),
            for (final action in footerActions)
              _SidebarItem(action, extended: extended),
          ],
        ],
      ),
    );
  }
}

class _SidebarItem extends StatelessWidget {
  const _SidebarItem(this.action, {required this.extended});

  final SidebarAction action;
  final bool extended;

  static const double _height = 32;
  static const double _iconSize = 18;

  /// Width of the labelled row: the extended sidebar minus the item's outer
  /// margin and the row's own horizontal padding.
  static const double _extendedContentWidth =
      VaultSidebar.extendedWidth - 4 * Insets.sm;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final enabled = action.enabled;
    final label = action.label;
    final disabled = scheme.onSurface.withValues(alpha: 0.38);
    final foreground = enabled ? scheme.onSurface : disabled;
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppTheme.controlRadius),
    );

    // Sidebar icons take the accent colour (HIG, Sidebars).
    final iconWidget = Icon(
      action.icon,
      size: _iconSize,
      color: enabled ? scheme.primary : disabled,
    );

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
                      Gaps.w8,
                      Expanded(
                        child: Text(
                          label,
                          maxLines: 1,
                          softWrap: false,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium?.copyWith(
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
      padding: const EdgeInsets.symmetric(horizontal: Insets.sm, vertical: 1),
      child: Material(
        color: Colors.transparent,
        shape: shape,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: enabled ? action.onPressed : null,
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
    padding: EdgeInsets.symmetric(horizontal: Insets.md, vertical: Insets.sm),
    child: Divider(height: 1),
  );
}
