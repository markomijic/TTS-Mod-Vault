/// The network settings the download operations depend on. Phase 5 folds
/// them into the full `Settings` model; until then they are persisted on
/// their own under [NetworkOptionsController.storageKey].
library;

import 'dart:convert';

import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:tts_mod_vault/app/theme/theme_controller.dart'
    show keyValueStoreProvider;
import 'package:tts_mod_vault/core/storage/key_value_store.dart';

/// Download concurrency and the domains never requested.
final class NetworkOptions {
  /// Creates the options.
  const NetworkOptions({
    this.concurrentDownloads = defaultConcurrentDownloads,
    this.ignoredDomains = const [],
  });

  /// Reads options from their JSON form; malformed fields fall back to the
  /// defaults.
  factory NetworkOptions.fromJson(Map<String, Object?> json) {
    final domains = json['ignoredDomains'];
    return NetworkOptions(
      concurrentDownloads: switch (json['concurrentDownloads']) {
        final int value when value >= 1 => value.clamp(1, maxConcurrent),
        _ => defaultConcurrentDownloads,
      },
      ignoredDomains: domains is List
          ? List.unmodifiable([
              for (final domain in domains)
                if (domain is String && domain.trim().isNotEmpty) domain.trim(),
            ])
          : const [],
    );
  }

  /// The v2 default.
  static const int defaultConcurrentDownloads = 5;

  /// Upper bound accepted for [concurrentDownloads].
  static const int maxConcurrent = 20;

  /// The defaults.
  static const NetworkOptions defaults = NetworkOptions();

  /// Files downloaded (or URLs checked) at the same time.
  final int concurrentDownloads;

  /// Host substrings whose URLs are skipped when downloading.
  final List<String> ignoredDomains;

  /// JSON form for the key-value store.
  Map<String, Object?> toJson() => {
    'concurrentDownloads': concurrentDownloads,
    'ignoredDomains': ignoredDomains,
  };

  /// Copy with some fields replaced.
  NetworkOptions copyWith({
    int? concurrentDownloads,
    List<String>? ignoredDomains,
  }) => NetworkOptions(
    concurrentDownloads: concurrentDownloads ?? this.concurrentDownloads,
    ignoredDomains: ignoredDomains ?? this.ignoredDomains,
  );

  @override
  bool operator ==(Object other) =>
      other is NetworkOptions &&
      other.concurrentDownloads == concurrentDownloads &&
      other.ignoredDomains.length == ignoredDomains.length &&
      _sameDomains(other.ignoredDomains);

  bool _sameDomains(List<String> other) {
    for (var i = 0; i < other.length; i++) {
      if (other[i] != ignoredDomains[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode =>
      Object.hash(concurrentDownloads, Object.hashAll(ignoredDomains));

  @override
  String toString() =>
      'NetworkOptions(concurrentDownloads: $concurrentDownloads, '
      'ignoredDomains: $ignoredDomains)';
}

/// Holds the current [NetworkOptions] and persists changes as JSON in the
/// key-value store. Starts with the defaults and swaps in the stored value
/// when the store answers, unless something was changed in the meantime.
final class NetworkOptionsController extends Notifier<NetworkOptions> {
  /// Store key under which the options JSON lives.
  static const String storageKey = 'network.options';

  bool _touched = false;
  late Future<void> _loaded;

  /// Waits until the stored options have been read (or found absent) and
  /// returns the current options.
  Future<NetworkOptions> ensureLoaded() async {
    await _loaded;
    return state;
  }

  @override
  NetworkOptions build() {
    final store = ref.watch(keyValueStoreProvider);
    _touched = false;
    _loaded = _restore(store);
    return NetworkOptions.defaults;
  }

  Future<void> _restore(KeyValueStore store) async {
    final raw = await store.read(storageKey);
    if (!ref.mounted || _touched || raw == null) return;
    try {
      final json = jsonDecode(raw);
      if (json is Map<String, Object?>) {
        state = NetworkOptions.fromJson(json);
      }
    } on FormatException {
      // Corrupt record: keep defaults; the next write replaces it.
    }
  }

  /// Replaces the options and persists them.
  Future<void> set(NetworkOptions options) async {
    _touched = true;
    state = options;
    await ref
        .read(keyValueStoreProvider)
        .write(storageKey, jsonEncode(options.toJson()));
  }

  /// Sets the download concurrency (clamped to `1..maxConcurrent`).
  Future<void> setConcurrentDownloads(int value) => set(
    state.copyWith(
      concurrentDownloads: value.clamp(1, NetworkOptions.maxConcurrent),
    ),
  );

  /// Sets the ignored domains.
  Future<void> setIgnoredDomains(List<String> domains) => set(
    state.copyWith(
      ignoredDomains: List.unmodifiable([
        for (final domain in domains)
          if (domain.trim().isNotEmpty) domain.trim(),
      ]),
    ),
  );
}

/// Provides the current [NetworkOptions].
final networkOptionsProvider =
    NotifierProvider<NetworkOptionsController, NetworkOptions>(
      NetworkOptionsController.new,
    );
