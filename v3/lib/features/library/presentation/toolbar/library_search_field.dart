import 'dart:async' show Timer;

import 'package:flutter_hooks/flutter_hooks.dart'
    show useEffect, useRef, useTextEditingController;
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tts_mod_vault/app/widgets/insets.dart';
import 'package:tts_mod_vault/features/library/application/library_view_providers.dart';
import 'package:tts_mod_vault/l10n/generated/app_localizations.dart';

/// Delay between the last keystroke and the filter update.
const Duration searchDebounce = Duration(milliseconds: 150);

/// Width of the field.
const double _width = 260;

/// Height of the field, matching the toolbar buttons.
const double _height = 40;

/// Compact search field bound to `ModFilterController.setQuery` with a
/// [searchDebounce] delay and a clear button. The text follows the provider
/// too, so a query cleared elsewhere (type switch, "Clear all filters")
/// empties the field.
class LibrarySearchField extends HookConsumerWidget {
  /// Creates the field. [focusNode] lets the page focus it on Ctrl+F.
  const LibrarySearchField({super.key, this.focusNode});

  /// Focus node of the text field.
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final initialQuery = ref.read(modFilterProvider).query;
    final controller = useTextEditingController(text: initialQuery);
    final timer = useRef<Timer?>(null);

    useEffect(
      () =>
          () => timer.value?.cancel(),
      const [],
    );

    ref.listen(modFilterProvider.select((f) => f.query), (_, query) {
      if (controller.text != query) {
        timer.value?.cancel();
        controller.text = query;
      }
    });

    void commit(String value) =>
        ref.read(modFilterProvider.notifier).setQuery(value);

    void onChanged(String value) {
      timer.value?.cancel();
      timer.value = Timer(searchDebounce, () => commit(value));
    }

    void clear() {
      timer.value?.cancel();
      controller.clear();
      commit('');
    }

    return SizedBox(
      width: _width,
      height: _height,
      child: ValueListenableBuilder<TextEditingValue>(
        valueListenable: controller,
        builder: (context, value, _) => TextField(
          controller: controller,
          focusNode: focusNode,
          onChanged: onChanged,
          onSubmitted: commit,
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            isDense: true,
            hintText: l10n.searchHint,
            prefixIcon: const Icon(Icons.search),
            suffixIcon: value.text.isEmpty
                ? null
                : IconButton(
                    tooltip: l10n.searchClear,
                    icon: const Icon(Icons.clear),
                    onPressed: clear,
                  ),
            filled: true,
            fillColor: scheme.surfaceContainerHighest,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: Insets.md,
              vertical: Insets.sm,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(_height / 2),
              borderSide: BorderSide.none,
            ),
          ),
        ),
      ),
    );
  }
}
