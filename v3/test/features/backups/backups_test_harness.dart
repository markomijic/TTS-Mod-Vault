// Fixtures for the Backups tab widget tests: five backups across two
// folders, three of them matched to mods of the library presentation
// fixture, served by the same spy controller and pump helper as the mods
// tests.

import 'package:path/path.dart' as p;
import 'package:tts_mod_vault/domain/models/models.dart';
import 'package:tts_mod_vault/features/library/application/library_controller.dart';

import '../library/presentation/presentation_test_harness.dart';

/// One mebibyte.
const int mib = 1024 * 1024;

/// Builds a backup under `<backupsDir>/<folder>/<fileName>`.
Backup fixtureBackup(
  String fileName, {
  required String folder,
  required DateTime modified,
  required int sizeBytes,
  required int assetCount,
  Mod? matchingMod,
}) => Backup(
  path: p.normalize(p.join(fixtureDirectories.backupsDir, folder, fileName)),
  fileName: fileName,
  folder: folder,
  modified: modified,
  sizeBytes: sizeBytes,
  assetCount: assetCount,
  matchingModPath: matchingMod?.jsonPath,
);

/// The fixed backups every Backups tab test renders.
///
/// Default A-Z order: Alpha, Beta, Gamma, Old Thing, Zeta Pack.
///
/// | file               | folder  | size    | modified   | assets | mod   |
/// |--------------------|---------|---------|------------|--------|-------|
/// | Alpha Mod.ttsmod   | Weekly  | 3.0 MB  | 2024-02-01 | 4      | Alpha |
/// | Beta Mod.ttsmod    | Weekly  | 7.0 MB  | 2024-01-10 | 3      | Beta  |
/// | Gamma Mod.ttsmod   | Archive | 2.0 MB  | 2023-12-01 | 9      | Gamma |
/// | Old Thing.ttsmod   | Archive | 1.5 MB  | 2023-06-01 | 2      | none  |
/// | Zeta Pack.ttsmod   | Weekly  | 12.0 MB | 2024-04-01 | 20     | none  |
final class FixtureBackups {
  /// Builds the backups matched against [library].
  FixtureBackups(this.library);

  /// The mods the matched backups point at.
  final FixtureLibrary library;

  late final Backup alpha = fixtureBackup(
    'Alpha Mod.ttsmod',
    folder: 'Weekly',
    modified: DateTime(2024, 2, 1, 12),
    sizeBytes: 3 * mib,
    assetCount: 4,
    matchingMod: library.alpha,
  );

  late final Backup beta = fixtureBackup(
    'Beta Mod.ttsmod',
    folder: 'Weekly',
    modified: DateTime(2024, 1, 10, 9, 30),
    sizeBytes: 7 * mib,
    assetCount: 3,
    matchingMod: library.beta,
  );

  late final Backup gamma = fixtureBackup(
    'Gamma Mod.ttsmod',
    folder: 'Archive',
    modified: DateTime(2023, 12, 1, 18),
    sizeBytes: 2 * mib,
    assetCount: 9,
    matchingMod: library.gamma,
  );

  late final Backup oldThing = fixtureBackup(
    'Old Thing.ttsmod',
    folder: 'Archive',
    modified: DateTime(2023, 6, 1, 8),
    sizeBytes: 3 * mib ~/ 2,
    assetCount: 2,
  );

  late final Backup zetaPack = fixtureBackup(
    'Zeta Pack.ttsmod',
    folder: 'Weekly',
    modified: DateTime(2024, 4, 1, 20, 15),
    sizeBytes: 12 * mib,
    assetCount: 20,
  );

  /// Every fixture backup, in no particular order.
  List<Backup> get all => [zetaPack, alpha, oldThing, gamma, beta];

  /// The library state with the mods, the save and these backups.
  LibraryState get state => LibraryState(
    mods: library.mods,
    saves: [library.save],
    backups: all,
    lastRefresh: DateTime(2024, 5),
  );
}
