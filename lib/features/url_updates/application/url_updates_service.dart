/// Facade the UI calls for "Update URL prefixes": builds the operation and
/// hands it to the `OperationRunner`.
library;

import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:tts_mod_vault/domain/models/models.dart';
import 'package:tts_mod_vault/features/operations/application/operation_runner.dart';
import 'package:tts_mod_vault/features/url_updates/application/update_urls_operation.dart';
import 'package:tts_mod_vault/features/url_updates/application/url_prefix_rules.dart'
    as rules;

export 'package:tts_mod_vault/features/url_updates/application/update_urls_operation.dart'
    show UpdateUrlsResult, updateUrlsProgressLabel;
export 'package:tts_mod_vault/features/url_updates/application/url_prefix_rules.dart'
    show UpdateUrlPrefixesResult, applyUrlPrefixes, isLegacyHostRewrite;
export 'package:tts_mod_vault/features/url_updates/application/url_replacement_preset.dart';

/// The URL updates facade.
final urlUpdatesServiceProvider = Provider<UrlUpdatesService>(
  UrlUpdatesService.new,
);

/// Starts URL prefix updates on the runner. [updateUrls] throws
/// [StateError] when another operation is running; cancellation comes back
/// in the result. Not `final`, so widget tests can substitute a fake.
class UrlUpdatesService {
  /// Creates the service on [ref].
  UrlUpdatesService(this.ref);

  /// Supplies the runner and the operation's collaborators.
  final Ref ref;

  /// Rewrites the URLs of [mods] starting with any of [oldPrefixes] to
  /// start with [newPrefix]; with [renameFiles] the cached files follow.
  Future<UpdateUrlsResult> updateUrls(
    List<Mod> mods, {
    required List<String> oldPrefixes,
    required String newPrefix,
    bool renameFiles = false,
  }) => ref
      .read(operationRunnerProvider.notifier)
      .run(
        UpdateUrlsOperation(
          ref: ref,
          mods: mods,
          oldPrefixes: oldPrefixes,
          newPrefix: newPrefix,
          renameFiles: renameFiles,
        ),
      );

  /// Splits the dialog's "old prefixes" text on `|`, trimming and dropping
  /// empty parts.
  List<String> parseOldPrefixes(String input) => rules.parseOldPrefixes(input);

  /// Requests cancellation of the running operation.
  void cancel() => ref.read(operationRunnerProvider.notifier).cancel();
}
