/// The data side of the log panel (plan section 4.8): a batched view of the
/// `LogStore`, level / source / text filtering, the unseen-badge counter,
/// the persisted panel geometry and the log file's path.
library;

import 'dart:async';
import 'dart:convert';

import 'package:collection/collection.dart' show IterableExtension;
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:meta/meta.dart';
import 'package:tts_mod_vault/app/providers/app_log_provider.dart';
import 'package:tts_mod_vault/app/theme/theme_controller.dart'
    show keyValueStoreProvider;
import 'package:tts_mod_vault/core/logging/app_log.dart';
import 'package:tts_mod_vault/core/storage/key_value_store.dart';

/// How long [LogEntriesController] waits after an entry before publishing a
/// new snapshot, so a burst of thousands of lines rebuilds the list once.
const Duration logCoalesceInterval = Duration(milliseconds: 100);

/// The store's entries, oldest first, republished at most once per
/// [logCoalesceInterval] while entries arrive.
final class LogEntriesController extends Notifier<List<LogEntry>> {
  StreamSubscription<LogEntry>? _subscription;
  Timer? _timer;

  @override
  List<LogEntry> build() {
    final store = ref.watch(appLogProvider).store;
    _subscription = store.onEntry.listen((_) => _schedule(store));
    ref.onDispose(() {
      _subscription?.cancel();
      _timer?.cancel();
    });
    return store.entries;
  }

  void _schedule(LogStore store) {
    _timer ??= Timer(logCoalesceInterval, () {
      _timer = null;
      if (ref.mounted) state = store.entries;
    });
  }

  /// Publishes the store's current entries now, without waiting for the
  /// coalescing timer (tests, and "copy all" right after an action).
  void flush() {
    _timer?.cancel();
    _timer = null;
    if (ref.mounted) state = ref.read(appLogProvider).store.entries;
  }

  /// Removes every entry from the store and the view. The store's unseen
  /// counter is reset by `LogStore.clear`; [UnseenLogCountController]
  /// picks that up from the state change (see `LogsService.clearLogs`).
  void clear() {
    ref.read(appLogProvider).store.clear();
    _timer?.cancel();
    _timer = null;
    state = const [];
  }
}

/// The log entries shown by the panel.
final logEntriesProvider =
    NotifierProvider<LogEntriesController, List<LogEntry>>(
      LogEntriesController.new,
    );

/// Which entries the panel shows. Empty [levels] / [sources] mean "no
/// restriction"; [LogLevel.debug] entries are hidden unless [showDebug]
/// is set, whatever [levels] says; [query] is a case-insensitive substring
/// match on message, details, URL and mod path.
@immutable
final class LogFilter {
  /// Creates a filter.
  const LogFilter({
    this.levels = const {},
    this.sources = const {},
    this.query = '',
    this.showDebug = false,
  });

  /// Everything but debug entries.
  static const LogFilter all = LogFilter();

  /// Levels to keep (empty: all).
  final Set<LogLevel> levels;

  /// Sources to keep (empty: all).
  final Set<LogSource> sources;

  /// Search text.
  final String query;

  /// Whether debug entries are shown.
  final bool showDebug;

  /// Whether no restriction beyond the debug default is active.
  bool get isEmpty => levels.isEmpty && sources.isEmpty && query.trim().isEmpty;

  /// Whether [entry] passes the filter.
  bool matches(LogEntry entry) {
    if (entry.level == LogLevel.debug && !showDebug) return false;
    if (levels.isNotEmpty && !levels.contains(entry.level)) return false;
    if (sources.isNotEmpty && !sources.contains(entry.source)) return false;
    final needle = query.trim().toLowerCase();
    if (needle.isEmpty) return true;
    return entry.message.toLowerCase().contains(needle) ||
        (entry.details?.toLowerCase().contains(needle) ?? false) ||
        (entry.url?.toLowerCase().contains(needle) ?? false) ||
        (entry.modPath?.toLowerCase().contains(needle) ?? false);
  }

  /// Copy with some fields replaced.
  LogFilter copyWith({
    Set<LogLevel>? levels,
    Set<LogSource>? sources,
    String? query,
    bool? showDebug,
  }) => LogFilter(
    levels: levels ?? this.levels,
    sources: sources ?? this.sources,
    query: query ?? this.query,
    showDebug: showDebug ?? this.showDebug,
  );

  @override
  bool operator ==(Object other) =>
      other is LogFilter &&
      other.query == query &&
      other.showDebug == showDebug &&
      other.levels.length == levels.length &&
      other.levels.containsAll(levels) &&
      other.sources.length == sources.length &&
      other.sources.containsAll(sources);

  @override
  int get hashCode => Object.hash(
    Object.hashAllUnordered(levels),
    Object.hashAllUnordered(sources),
    query,
    showDebug,
  );

  @override
  String toString() =>
      'LogFilter(levels: $levels, sources: $sources, query: "$query"'
      '${showDebug ? ', showDebug' : ''})';
}

/// Edits the current [LogFilter].
final class LogFilterController extends Notifier<LogFilter> {
  @override
  LogFilter build() => LogFilter.all;

  /// Adds [level] to the level filter, or removes it when present.
  void toggleLevel(LogLevel level) {
    final levels = Set<LogLevel>.of(state.levels);
    if (!levels.remove(level)) levels.add(level);
    state = state.copyWith(levels: Set.unmodifiable(levels));
  }

  /// Adds [source] to the source filter, or removes it when present.
  void toggleSource(LogSource source) {
    final sources = Set<LogSource>.of(state.sources);
    if (!sources.remove(source)) sources.add(source);
    state = state.copyWith(sources: Set.unmodifiable(sources));
  }

  /// Sets the search text.
  void setQuery(String query) => state = state.copyWith(query: query);

  /// Shows or hides debug entries.
  void setShowDebug(bool value) => state = state.copyWith(showDebug: value);

  /// Replaces the whole filter.
  void set(LogFilter filter) => state = filter;

  /// Clears levels, sources and search text; keeps the debug switch.
  void clear() => state = LogFilter(showDebug: state.showDebug);
}

/// The current [LogFilter].
final logFilterProvider = NotifierProvider<LogFilterController, LogFilter>(
  LogFilterController.new,
);

/// The entries of [logEntriesProvider] that pass [logFilterProvider],
/// oldest first.
final filteredLogEntriesProvider = Provider<List<LogEntry>>((ref) {
  final entries = ref.watch(logEntriesProvider);
  final filter = ref.watch(logFilterProvider);
  if (filter.isEmpty && filter.showDebug) return entries;
  return List.unmodifiable([
    for (final entry in entries)
      if (filter.matches(entry)) entry,
  ]);
});

/// Warnings and errors logged since the panel was last expanded (the
/// header badge). Follows the store's own counter, re-read with every
/// entries snapshot; [markSeen] resets it.
final class UnseenLogCountController extends Notifier<int> {
  @override
  int build() {
    final store = ref.watch(appLogProvider).store;
    ref.listen(logEntriesProvider, (_, _) {
      if (ref.mounted) state = store.unseenWarningsAndErrors;
    });
    return store.unseenWarningsAndErrors;
  }

  /// Resets the counter (the user expanded the panel).
  void markSeen() {
    ref.read(appLogProvider).store.markSeen();
    state = 0;
  }
}

/// Unseen warnings and errors.
final unseenLogCountProvider = NotifierProvider<UnseenLogCountController, int>(
  UnseenLogCountController.new,
);

/// Collapsed / expanded state and height of the log panel, persisted under
/// [LogPanelStateController.storageKey].
@immutable
final class LogPanelState {
  /// Creates a state.
  const LogPanelState({this.expanded = false, this.height = defaultHeight});

  /// Reads a state from JSON; malformed fields keep their default.
  factory LogPanelState.fromJson(Map<String, Object?> json) => LogPanelState(
    expanded: switch (json['expanded']) {
      final bool value => value,
      _ => false,
    },
    height: switch (json['height']) {
      final num value => clampHeight(value.toDouble()),
      _ => defaultHeight,
    },
  );

  /// Height of the expanded panel at first use.
  static const double defaultHeight = 220;

  /// Smallest height the drag handle allows.
  static const double minHeight = 120;

  /// Largest height the drag handle allows.
  static const double maxHeight = 800;

  /// The initial state: collapsed, default height.
  static const LogPanelState collapsed = LogPanelState();

  /// Whether the list is shown.
  final bool expanded;

  /// Height of the expanded panel in logical pixels.
  final double height;

  /// Clamps [height] to [minHeight]..[maxHeight].
  static double clampHeight(double height) =>
      height.clamp(minHeight, maxHeight).toDouble();

  /// JSON form.
  Map<String, Object?> toJson() => {'expanded': expanded, 'height': height};

  /// Copy with some fields replaced.
  LogPanelState copyWith({bool? expanded, double? height}) => LogPanelState(
    expanded: expanded ?? this.expanded,
    height: height ?? this.height,
  );

  @override
  bool operator ==(Object other) =>
      other is LogPanelState &&
      other.expanded == expanded &&
      other.height == height;

  @override
  int get hashCode => Object.hash(expanded, height);

  @override
  String toString() => 'LogPanelState(expanded: $expanded, height: $height)';
}

/// Holds the [LogPanelState] and persists it. Expanding the panel marks the
/// unseen warnings and errors as seen.
final class LogPanelStateController extends Notifier<LogPanelState> {
  /// Store key under which the state JSON lives.
  static const String storageKey = 'logPanel';

  bool _touched = false;

  @override
  LogPanelState build() {
    final store = ref.watch(keyValueStoreProvider);
    _touched = false;
    _restore(store);
    return LogPanelState.collapsed;
  }

  Future<void> _restore(KeyValueStore store) async {
    final raw = await store.read(storageKey);
    if (!ref.mounted || _touched || raw == null) return;
    try {
      final json = jsonDecode(raw);
      if (json is Map<String, Object?>) {
        state = LogPanelState.fromJson(json);
      }
    } on FormatException {
      // Corrupt record: keep defaults; the next write replaces it.
    }
  }

  /// Replaces and persists the state.
  Future<void> set(LogPanelState panel) async {
    _touched = true;
    state = panel;
    if (panel.expanded) ref.read(unseenLogCountProvider.notifier).markSeen();
    await ref
        .read(keyValueStoreProvider)
        .write(storageKey, jsonEncode(panel.toJson()));
  }

  /// Expands or collapses the panel.
  Future<void> setExpanded(bool value) => set(state.copyWith(expanded: value));

  /// Flips between expanded and collapsed.
  Future<void> toggle() => setExpanded(!state.expanded);

  /// Sets the expanded height (clamped).
  Future<void> setHeight(double height) =>
      set(state.copyWith(height: LogPanelState.clampHeight(height)));
}

/// The log panel's persisted state.
final logPanelStateProvider =
    NotifierProvider<LogPanelStateController, LogPanelState>(
      LogPanelStateController.new,
    );

/// Path of the current log file, from the `RotatingFileLogSink` among the
/// log's sinks; null when the log has no file sink (tests).
final logFilePathProvider = Provider<String?>(
  (ref) => ref
      .watch(appLogProvider)
      .sinks
      .whereType<RotatingFileLogSink>()
      .firstOrNull
      ?.filePath,
);

/// Small facade for the panel's actions.
final logsServiceProvider = Provider<LogsService>(LogsService.new);

/// The actions of the log panel header that are not plain state edits.
class LogsService {
  /// Creates the service on [ref].
  LogsService(this.ref);

  /// Supplies the providers.
  final Ref ref;

  /// Removes every entry (store and view) and resets the unseen badge.
  void clearLogs() {
    ref.read(logEntriesProvider.notifier).clear();
    ref.read(unseenLogCountProvider.notifier).markSeen();
  }

  /// Resets the unseen badge.
  void markLogsSeen() => ref.read(unseenLogCountProvider.notifier).markSeen();

  /// The visible entries rendered as log-file lines, for "copy all".
  String copyVisibleText() =>
      [for (final entry in ref.read(filteredLogEntriesProvider)) entry.toLine()]
          .join('\n');
}
