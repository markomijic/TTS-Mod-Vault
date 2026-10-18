import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:tts_mod_vault/app/providers/infrastructure_providers.dart';
import 'package:tts_mod_vault/domain/models/models.dart';
import 'package:tts_mod_vault/features/library/application/library_controller.dart';
import 'package:tts_mod_vault/features/library/application/library_settings.dart';

/// Assets of the mod at the given normalised JSON path, honouring the mod's
/// audio visibility override and the global ignore-audio option.
///
/// Re-fetched whenever the mod's entry in the library state changes (a
/// summary patch after downloads, deletes or edits, an audio visibility
/// change) and whenever the global audio option flips; the edit service also
/// invalidates it explicitly after its own writes. Disposed when the detail
/// view stops watching it. A path that is not in the library yields the
/// store's assets with audio shown or hidden by the global option alone.
final modAssetsProvider = FutureProvider.autoDispose
    .family<List<Asset>, String>((ref, jsonPath) async {
      final mod = ref.watch(
        libraryControllerProvider.select((s) => s.value?.modByPath(jsonPath)),
      );
      final ignoreAudioGlobally = ref.watch(
        libraryOptionsProvider.select((o) => o.ignoreAudioGlobally),
      );
      final audio = mod?.audio ?? AudioVisibility.useGlobalSetting;
      final includeAudio = !audio.hideAudio(
        ignoreAudioGlobally: ignoreAudioGlobally,
      );
      return ref
          .watch(appDatabaseProvider)
          .libraryQueries
          .assetsForMod(jsonPath, includeAudio: includeAudio);
    });
