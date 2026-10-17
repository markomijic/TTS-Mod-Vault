import 'dart:async' show Timer;

import 'package:flutter_hooks/flutter_hooks.dart'
    show useEffect, useRef, useTextEditingController;
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:hooks_riverpod/misc.dart' show ProviderListenable;
import 'package:material_ui/material_ui.dart';
import 'package:tts_mod_vault/app/widgets/insets.dart';
import 'package:tts_mod_vault/l10n/generated/app_localizations.dart';

/// Delay between the last keystroke and the filter update.
const Duration searchDebounce = Duration(milliseconds: 150);

/// Width of the field.
const double _width = 260;

/// Height of the field, matching the toolbar buttons.
const double _height = 40;

/// Compact search field bound to a provider-held query: edits reach
/// [onQueryChanged] after a [searchDebounce] delay (or at once on submit and
/// clear), and the text follows [query] too, so a query cleared elsewhere
/// (tab switch, "Clear all filters") empties the field.
class DebouncedSearchField extends HookConsumerWidget {
  /// Creates the field. [focusNode] lets the page focus it on Ctrl+F.
  const DebouncedSearchField({
    super.key,
    required this.query,
    required this.onQueryChanged,
    this.focusNode,
  });

  /// The query as the filter holds it.
  final ProviderListenable<String> query;

  /// Writes the query to the filter.
  final ValueChanged<String> onQueryChanged;

  /// Focus node of the text field.
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final initialQuery = ref.read(query);
    final controller = useTextEditingController(text: initialQuery);
    final timer = useRef<Timer?>(null);

    useEffect(
      () =>
          () => timer.value?.cancel(),
      const [],
    );

    ref.listen(query, (_, value) {
      if (controller.text != value) {
        timer.value?.cancel();
        controller.text = value;
      }
    });

    void onChanged(String value) {
      timer.value?.cancel();
      timer.value = Timer(searchDebounce, () => onQueryChanged(value));
    }

    void clear() {
      timer.value?.cancel();
      controller.clear();
      onQueryChanged('');
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
          onSubmitted: onQueryChanged,
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
