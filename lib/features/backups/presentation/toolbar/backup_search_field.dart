import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tts_mod_vault/features/library/application/backup_view_providers.dart';
import 'package:tts_mod_vault/features/library/presentation/toolbar/debounced_search_field.dart';

/// The Backups tab's search field: a [DebouncedSearchField] bound to
/// `BackupFilterController.setQuery`.
class BackupSearchField extends ConsumerWidget {
  /// Creates the field. [focusNode] lets the page focus it on Ctrl+F.
  const BackupSearchField({super.key, this.focusNode});

  /// Focus node of the text field.
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context, WidgetRef ref) => DebouncedSearchField(
    query: backupFilterProvider.select((f) => f.query),
    onQueryChanged: ref.read(backupFilterProvider.notifier).setQuery,
    focusNode: focusNode,
  );
}
