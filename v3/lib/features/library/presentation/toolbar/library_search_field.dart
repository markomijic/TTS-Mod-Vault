import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tts_mod_vault/features/library/application/library_view_providers.dart';
import 'package:tts_mod_vault/features/library/presentation/toolbar/debounced_search_field.dart';

export 'package:tts_mod_vault/features/library/presentation/toolbar/debounced_search_field.dart'
    show searchDebounce;

/// The mod tabs' search field: a [DebouncedSearchField] bound to
/// `ModFilterController.setQuery`.
class LibrarySearchField extends ConsumerWidget {
  /// Creates the field. [focusNode] lets the page focus it on Ctrl+F.
  const LibrarySearchField({super.key, this.focusNode});

  /// Focus node of the text field.
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context, WidgetRef ref) => DebouncedSearchField(
    query: modFilterProvider.select((f) => f.query),
    onQueryChanged: ref.read(modFilterProvider.notifier).setQuery,
    focusNode: focusNode,
  );
}
