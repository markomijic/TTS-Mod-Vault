/// The collapsible, resizable log panel of plan section 4.8, docked under
/// the library list next to the operation progress bar.
library;

import 'dart:async' show Timer;

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter_hooks/flutter_hooks.dart'
    show useEffect, useRef, useScrollController, useState;
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tts_mod_vault/app/widgets/app_dialog.dart';
import 'package:tts_mod_vault/app/widgets/insets.dart';
import 'package:tts_mod_vault/features/library/presentation/item_actions.dart';
import 'package:tts_mod_vault/features/library/presentation/toolbar/debounced_search_field.dart';
import 'package:tts_mod_vault/features/logs/application/log_providers.dart';
import 'package:tts_mod_vault/features/logs/presentation/log_entry_row.dart';
import 'package:tts_mod_vault/features/logs/presentation/log_labels.dart';
import 'package:tts_mod_vault/features/logs/presentation/log_panel_header.dart';
import 'package:tts_mod_vault/l10n/generated/app_localizations.dart';

export 'package:tts_mod_vault/features/logs/presentation/log_panel_header.dart'
    show logHeaderFlashDuration, logHeaderHeight;

/// Height of the drag handle on the top edge of the expanded panel.
const double _handleHeight = 8;

/// Width of the drag handle's grip line.
const double _gripWidth = 40;

/// Thickness of the grip line.
const double _gripThickness = 3;

/// How far (in pixels) the list may sit above the newest entry and still
/// count as following the tail.
const double _followThreshold = 24;

/// Duration of the "Jump to latest" scroll.
const Duration _jumpDuration = Duration(milliseconds: 200);

/// The log panel: a [LogPanelHeader] when collapsed; when expanded, a drag
/// handle, the header, the filter toolbar and the entry list at the
/// persisted height ([logPanelStateProvider]).
///
/// A warning or error that arrives while the panel is collapsed flashes
/// the header once (the badge count comes from [unseenLogCountProvider]);
/// the panel never expands by itself. Expanding marks the entries seen,
/// and entries that arrive while the list is open count as seen too.
class LogPanel extends HookConsumerWidget {
  /// Creates the panel.
  const LogPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final panel = ref.watch(logPanelStateProvider);
    final notifier = ref.read(logPanelStateProvider.notifier);
    final flashing = useState(false);
    final flashTimer = useRef<Timer?>(null);
    final dragHeight = useState<double?>(null);

    useEffect(
      () =>
          () => flashTimer.value?.cancel(),
      const [],
    );

    ref.listen(unseenLogCountProvider, (previous, next) {
      if (next <= (previous ?? 0)) return;
      if (ref.read(logPanelStateProvider).expanded) {
        // The list is on screen, so the new entry is seen right away.
        ref.read(logsServiceProvider).markLogsSeen();
        return;
      }
      flashTimer.value?.cancel();
      flashing.value = true;
      flashTimer.value = Timer(logHeaderFlashDuration, () {
        flashing.value = false;
      });
    });

    void toggle() {
      notifier.toggle();
      if (!ref.read(logPanelStateProvider).expanded) return;
      ref.read(logsServiceProvider).markLogsSeen();
    }

    final header = LogPanelHeader(
      expanded: panel.expanded,
      flashing: flashing.value,
      onToggle: toggle,
    );

    return Material(
      color: scheme.surfaceContainerLow,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (panel.expanded)
            _DragHandle(
              onDragUpdate: (delta) =>
                  dragHeight.value = LogPanelState.clampHeight(
                    (dragHeight.value ?? panel.height) - delta,
                  ),
              onDragEnd: () {
                final height = dragHeight.value;
                dragHeight.value = null;
                if (height != null) notifier.setHeight(height);
              },
            ),
          header,
          if (panel.expanded)
            SizedBox(
              height: dragHeight.value ?? panel.height,
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _LogToolbar(),
                  Divider(height: 1),
                  Expanded(child: _LogList()),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// The resize grip on the panel's top edge. Dragging up grows the panel.
class _DragHandle extends StatelessWidget {
  const _DragHandle({required this.onDragUpdate, required this.onDragEnd});

  /// Vertical pointer delta of the current drag.
  final ValueChanged<double> onDragUpdate;

  /// The drag finished; persist the height.
  final VoidCallback onDragEnd;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: l10n.logPanelResize,
      waitDuration: const Duration(seconds: 1),
      child: MouseRegion(
        cursor: SystemMouseCursors.resizeRow,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onVerticalDragUpdate: (details) => onDragUpdate(details.delta.dy),
          onVerticalDragEnd: (_) => onDragEnd(),
          onVerticalDragCancel: onDragEnd,
          child: SizedBox(
            height: _handleHeight,
            child: Center(
              child: Container(
                width: _gripWidth,
                height: _gripThickness,
                decoration: BoxDecoration(
                  color: scheme.outlineVariant,
                  borderRadius: BorderRadius.circular(_gripThickness),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Level chips, source menu, search, the debug toggle (debug builds), copy
/// visible and clear.
class _LogToolbar extends ConsumerWidget {
  const _LogToolbar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final filter = ref.watch(logFilterProvider);
    final filterNotifier = ref.read(logFilterProvider.notifier);
    final hasEntries = ref.watch(
      logEntriesProvider.select((entries) => entries.isNotEmpty),
    );
    final hasVisible = ref.watch(
      filteredLogEntriesProvider.select((entries) => entries.isNotEmpty),
    );

    Future<void> confirmClear() async {
      final confirmed = await showConfirmDialog(
        context,
        title: l10n.logClearTitle,
        message: l10n.logClearMessage,
        confirmLabel: l10n.logClear,
        destructive: true,
      );
      if (!confirmed || !context.mounted) return;
      ref.read(logsServiceProvider).clearLogs();
    }

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: Insets.sm,
        vertical: Insets.xs,
      ),
      child: Wrap(
        spacing: Insets.sm,
        runSpacing: Insets.xs,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          for (final level in logFilterLevels)
            FilterChip(
              avatar: Icon(level.icon, color: level.color(context)),
              label: Text(level.title(l10n)),
              selected: filter.levels.contains(level),
              visualDensity: VisualDensity.compact,
              onSelected: (_) => filterNotifier.toggleLevel(level),
            ),
          const _SourceMenu(),
          DebouncedSearchField(
            query: logFilterProvider.select((f) => f.query),
            onQueryChanged: filterNotifier.setQuery,
          ),
          if (kDebugMode)
            FilterChip(
              label: Text(l10n.logShowDebug),
              selected: filter.showDebug,
              visualDensity: VisualDensity.compact,
              onSelected: filterNotifier.setShowDebug,
            ),
          IconButton(
            tooltip: l10n.logCopyVisible,
            visualDensity: VisualDensity.compact,
            onPressed: hasVisible
                ? () => copyTextToClipboard(
                    context,
                    ref.read(logsServiceProvider).copyVisibleText(),
                  )
                : null,
            icon: const Icon(Icons.copy_all),
          ),
          IconButton(
            tooltip: l10n.logClear,
            visualDensity: VisualDensity.compact,
            onPressed: hasEntries ? confirmClear : null,
            icon: const Icon(Icons.delete_sweep_outlined),
          ),
        ],
      ),
    );
  }
}

/// "Sources" multi-select: a button with the count of chosen sources as a
/// badge, opening a menu of checkboxes.
class _SourceMenu extends ConsumerWidget {
  const _SourceMenu();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final sources = ref.watch(logFilterProvider.select((f) => f.sources));
    final notifier = ref.read(logFilterProvider.notifier);
    return MenuAnchor(
      menuChildren: [
        for (final source in logFilterSources)
          CheckboxMenuButton(
            value: sources.contains(source),
            closeOnActivate: false,
            onChanged: (_) => notifier.toggleSource(source),
            child: Text(source.title(l10n)),
          ),
      ],
      builder: (context, controller, _) => Badge.count(
        count: sources.length,
        isLabelVisible: sources.isNotEmpty,
        child: OutlinedButton.icon(
          onPressed: () =>
              controller.isOpen ? controller.close() : controller.open(),
          icon: const Icon(Icons.arrow_drop_down),
          iconAlignment: IconAlignment.end,
          label: Text(l10n.logFilterSources),
        ),
      ),
    );
  }
}

/// The virtualised entry list, newest at the bottom. The list is reversed
/// so offset zero is the newest entry: while the user sits there, new
/// entries stay in view (follow-tail); once they scroll up, the view holds
/// still and a "Jump to latest" chip appears.
class _LogList extends HookConsumerWidget {
  const _LogList();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final entries = ref.watch(filteredLogEntriesProvider);
    final controller = useScrollController();
    final following = useState(true);

    if (entries.isEmpty) {
      return Center(
        child: Text(
          l10n.logPanelEmpty,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }

    return Stack(
      children: [
        NotificationListener<ScrollNotification>(
          onNotification: (notification) {
            if (notification.metrics.axis == Axis.vertical) {
              final atTail = notification.metrics.pixels <= _followThreshold;
              if (atTail != following.value) following.value = atTail;
            }
            return false;
          },
          child: ListView.builder(
            controller: controller,
            reverse: true,
            padding: const EdgeInsets.symmetric(vertical: Insets.xs),
            itemCount: entries.length,
            itemBuilder: (context, index) {
              final entry = entries[entries.length - 1 - index];
              return LogEntryRow(key: ValueKey(entry.id), entry: entry);
            },
          ),
        ),
        if (!following.value)
          Positioned(
            right: Insets.lg,
            bottom: Insets.sm,
            child: ActionChip(
              avatar: const Icon(Icons.arrow_downward),
              label: Text(l10n.logJumpToLatest),
              onPressed: () => controller.animateTo(
                0,
                duration: _jumpDuration,
                curve: Curves.easeOut,
              ),
            ),
          ),
      ],
    );
  }
}
