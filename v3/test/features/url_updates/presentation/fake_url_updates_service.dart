// A `UrlUpdatesService` double: records `updateUrls` calls and answers
// with a configurable result; `parseOldPrefixes` stays real.

// Test doubles expose recorded calls on purpose.
// ignore_for_file: avoid_public_notifier_properties

import 'package:hooks_riverpod/misc.dart' show Override;
import 'package:tts_mod_vault/domain/models/models.dart';
import 'package:tts_mod_vault/features/url_updates/application/url_updates_service.dart';

/// One recorded `updateUrls` call.
typedef UrlUpdateCall = ({
  List<Mod> mods,
  List<String> oldPrefixes,
  String newPrefix,
  bool renameFiles,
});

/// Records calls and returns [result], or "every mod updated, 2 files
/// renamed" by default.
final class FakeUrlUpdatesService extends UrlUpdatesService {
  FakeUrlUpdatesService(super.ref);

  /// Every `updateUrls` call.
  final List<UrlUpdateCall> calls = [];

  /// Result override.
  UpdateUrlsResult? result;

  /// Whether calls throw as the runner does while something runs.
  bool alreadyRunning = false;

  @override
  Future<UpdateUrlsResult> updateUrls(
    List<Mod> mods, {
    required List<String> oldPrefixes,
    required String newPrefix,
    bool renameFiles = false,
  }) async {
    if (alreadyRunning) throw StateError('An operation is already running');
    calls.add((
      mods: mods,
      oldPrefixes: oldPrefixes,
      newPrefix: newPrefix,
      renameFiles: renameFiles,
    ));
    return result ??
        UpdateUrlsResult(
          modsProcessed: mods.length,
          modsUpdated: mods.length,
          filesRenamed: 2,
          failed: const [],
          cancelled: false,
        );
  }
}

/// Overrides `urlUpdatesServiceProvider` with a [FakeUrlUpdatesService].
Override fakeUrlUpdatesServiceOverride() =>
    urlUpdatesServiceProvider.overrideWith(FakeUrlUpdatesService.new);
