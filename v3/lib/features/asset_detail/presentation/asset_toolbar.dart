import 'dart:async' show Timer;

import 'package:flutter/services.dart' show KeyDownEvent, LogicalKeyboardKey;
import 'package:flutter_hooks/flutter_hooks.dart'
    show useEffect, useFocusNode, useRef, useState, useTextEditingController;
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tts_mod_vault/app/shell/operation_running_provider.dart'
    show operationRunningProvider;
import 'package:tts_mod_vault/app/widgets/app_snack_bar.dart';
import 'package:tts_mod_vault/app/widgets/insets.dart';
import 'package:tts_mod_vault/core/result/result.dart';
import 'package:tts_mod_vault/domain/models/models.dart';
import 'package:tts_mod_vault/features/asset_detail/application/asset_detail_filter.dart';
import 'package:tts_mod_vault/features/asset_detail/application/mod_assets_provider.dart';
import 'package:tts_mod_vault/features/asset_detail/presentation/asset_detail_labels.dart';
import 'package:tts_mod_vault/features/library/application/library_settings.dart';
import 'package:tts_mod_vault/features/library/application/mod_edit_service.dart';
import 'package:tts_mod_vault/features/library/presentation/library_labels.dart';
import 'package:tts_mod_vault/l10n/generated/app_localizations.dart';

/// Delay between the last keystroke in the URL search and the filter update.
const Duration assetSearchDebounce = Duration(milliseconds: 150);

/// Width of the expanded search field.
const double _searchWidth = 300;

/// Height of the toolbar controls.
const double _controlHeight = 40;

/// Filter row of the selected-mod view: status menu, audio override (when
/// the mod references audio), URL search, the "Invalid" chip (when the mod
/// has invalid URLs) and one chip per asset type the mod references.
///
/// Chips and the invalid flag are derived from the unfiltered
/// `modAssetsProvider` list so they do not disappear while a filter is
/// active.
class AssetToolbar extends ConsumerWidget {
  /// Creates the toolbar for [mod].
  const AssetToolbar({super.key, required this.mod});

  /// The selected mod.
  final Mod mod;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final assets = ref.watch(modAssetsProvider(mod.jsonPath)).value ?? const [];
    final filter = ref.watch(assetDetailFilterProvider);
    final notifier = ref.read(assetDetailFilterProvider.notifier);

    final presentTypes = <AssetType>{for (final asset in assets) asset.type};
    final hasInvalid = assets.any((asset) => asset.invalid);

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        Insets.lg,
        Insets.sm,
        Insets.sm,
        Insets.xs,
      ),
      child: Wrap(
        spacing: Insets.sm,
        runSpacing: Insets.xs,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          const _StatusFilterButton(),
          if (mod.summary.hasAudio) AudioVisibilityButton(mod: mod),
          const AssetSearchField(),
          if (hasInvalid)
            FilterChip(
              label: Text(l10n.assetInvalidChip),
              selected: filter.invalidOnly,
              showCheckmark: false,
              onSelected: notifier.setInvalidOnly,
            ),
          for (final type in AssetType.values)
            if (presentTypes.contains(type))
              FilterChip(
                label: Text(type.label(l10n)),
                selected: filter.type == type,
                showCheckmark: false,
                onSelected: (selected) =>
                    notifier.setType(selected ? type : null),
              ),
        ],
      ),
    );
  }
}

/// "All / Missing / Downloaded" menu; the button shows the active choice.
class _StatusFilterButton extends ConsumerWidget {
  const _StatusFilterButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final status = ref.watch(assetDetailFilterProvider.select((f) => f.status));

    return MenuAnchor(
      builder: (context, controller, _) => Tooltip(
        message: l10n.assetStatusFilterTooltip,
        child: OutlinedButton.icon(
          onPressed: controller.isOpen ? controller.close : controller.open,
          icon: const Icon(Icons.arrow_drop_down),
          label: Text(status.label(l10n)),
        ),
      ),
      menuChildren: [
        for (final option in AssetStatusFilter.values)
          MenuItemButton(
            leadingIcon: Icon(option == status ? Icons.check : null),
            onPressed: () =>
                ref.read(assetDetailFilterProvider.notifier).setStatus(option),
            child: Text(option.label(l10n)),
          ),
      ],
    );
  }
}

/// Per-mod audio visibility override (2.x `_AudioAssetsButton`): a speaker
/// icon, tinted while the mod overrides the global setting, with a menu of
/// the three [AudioVisibility] choices.
class AudioVisibilityButton extends ConsumerWidget {
  /// Creates the button for [mod].
  const AudioVisibilityButton({super.key, required this.mod});

  /// The selected mod.
  final Mod mod;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final ignoreGlobally = ref.watch(
      libraryOptionsProvider.select((o) => o.ignoreAudioGlobally),
    );
    final running = ref.watch(operationRunningProvider);

    final visibility = mod.audio;
    final hasOverride = visibility != AudioVisibility.useGlobalSetting;
    final showing = !visibility.hideAudio(ignoreAudioGlobally: ignoreGlobally);
    final globalState = ignoreGlobally
        ? l10n.audioStateHidden
        : l10n.audioStateShown;
    final tooltip = switch (visibility) {
      AudioVisibility.useGlobalSetting => l10n.audioVisibilityUsingGlobal(
        globalState,
      ),
      AudioVisibility.alwaysShow => l10n.audioVisibilityOverrideShow,
      AudioVisibility.alwaysHide => l10n.audioVisibilityOverrideHide,
    };
    final icon = Icon(showing ? Icons.volume_up : Icons.volume_off);

    Future<void> choose(AudioVisibility value) async {
      if (value == visibility) return;
      final service = ref.read(modEditServiceProvider);
      final result = await service.setAudioVisibility(mod, value);
      if (result case Err(:final failure) when context.mounted) {
        showAppSnackBar(context, failure.message);
      }
    }

    return MenuAnchor(
      builder: (context, controller, _) {
        final onPressed = running
            ? null
            : controller.isOpen
            ? controller.close
            : controller.open;
        return Tooltip(
          message: tooltip,
          child: hasOverride
              ? IconButton.filledTonal(onPressed: onPressed, icon: icon)
              : IconButton.outlined(onPressed: onPressed, icon: icon),
        );
      },
      menuChildren: [
        for (final (value, label, valueIcon) in [
          (
            AudioVisibility.useGlobalSetting,
            l10n.audioMenuUseGlobal(globalState),
            Icons.settings_outlined,
          ),
          (
            AudioVisibility.alwaysShow,
            l10n.audioMenuAlwaysShow,
            Icons.volume_up,
          ),
          (
            AudioVisibility.alwaysHide,
            l10n.audioMenuAlwaysHide,
            Icons.volume_off,
          ),
        ])
          MenuItemButton(
            leadingIcon: Icon(value == visibility ? Icons.check : null),
            trailingIcon: Icon(valueIcon),
            onPressed: () => choose(value),
            child: Text(label),
          ),
      ],
    );
  }
}

/// Search icon that expands into a [_searchWidth] wide field bound to
/// `AssetDetailFilterController.setQuery` with an [assetSearchDebounce]
/// delay. Esc or the clear button empties the query and collapses the
/// field; a query cleared elsewhere (mod switch) collapses it too.
class AssetSearchField extends HookConsumerWidget {
  /// Creates the field.
  const AssetSearchField({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final active = useState(
      ref.read(assetDetailFilterProvider).query.isNotEmpty,
    );
    final controller = useTextEditingController(
      text: ref.read(assetDetailFilterProvider).query,
    );
    final focusNode = useFocusNode(debugLabel: 'AssetSearch');
    final timer = useRef<Timer?>(null);

    useEffect(
      () =>
          () => timer.value?.cancel(),
      const [],
    );

    void commit(String value) =>
        ref.read(assetDetailFilterProvider.notifier).setQuery(value);

    void collapse() {
      timer.value?.cancel();
      controller.clear();
      commit('');
      active.value = false;
    }

    ref.listen(assetDetailFilterProvider.select((f) => f.query), (_, query) {
      if (controller.text == query) return;
      timer.value?.cancel();
      controller.text = query;
      if (query.isEmpty) active.value = false;
    });

    if (!active.value) {
      return IconButton.outlined(
        tooltip: l10n.assetSearchTooltip,
        icon: const Icon(Icons.search),
        onPressed: () {
          active.value = true;
          focusNode.requestFocus();
        },
      );
    }

    void onChanged(String value) {
      timer.value?.cancel();
      timer.value = Timer(assetSearchDebounce, () => commit(value));
    }

    return SizedBox(
      width: _searchWidth,
      height: _controlHeight,
      child: Focus(
        onKeyEvent: (node, event) {
          if (event is KeyDownEvent &&
              event.logicalKey == LogicalKeyboardKey.escape) {
            collapse();
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: TextField(
          controller: controller,
          focusNode: focusNode,
          autofocus: true,
          onChanged: onChanged,
          onSubmitted: commit,
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            isDense: true,
            hintText: l10n.assetSearchHint,
            prefixIcon: const Icon(Icons.search),
            suffixIcon: IconButton(
              tooltip: l10n.searchClear,
              icon: const Icon(Icons.clear),
              onPressed: collapse,
            ),
            filled: true,
            fillColor: scheme.surfaceContainerHighest,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: Insets.md,
              vertical: Insets.sm,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(_controlHeight / 2),
              borderSide: BorderSide.none,
            ),
          ),
        ),
      ),
    );
  }
}
