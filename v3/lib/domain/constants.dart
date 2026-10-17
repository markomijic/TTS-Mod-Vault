/// Shared constants for TTS and Steam conventions.
library;

/// Host TTS used for Steam Cloud assets until 2023; files cached under this
/// URL still exist on disk and in old mod JSONs.
const oldCloudUrl = 'http://cloud-3.steamusercontent.com/';

/// Current Steam user-content host. URLs and file keys are normalised to it.
const newSteamUserContentUrl = 'https://steamusercontent-a.akamaihd.net/';

/// Steam Web API endpoint used to fetch Workshop item details.
const steamPublishedFileDetailsUrl =
    'https://api.steampowered.com/ISteamRemoteStorage/GetPublishedFileDetails/v1/';

/// Tabletop Simulator's Steam app id (`consumer_app_id` on Workshop items).
const tabletopSimulatorAppId = 286160;

/// Files TTS writes next to mods/saves that are not mods themselves.
const ttsIndexFileNames = ['WorkshopFileInfos.json', 'SaveFileInfos.json'];

/// Folder names inside the TTS data directory.
const ttsModsFolder = 'Mods';
const ttsSavesFolder = 'Saves';
const ttsWorkshopFolder = 'Workshop';
const ttsSavedObjectsFolder = 'Saved Objects';
const ttsThumbnailsFolder = 'Thumbnails';

/// Backup archive extension (shared with TTS Mod Backup).
const ttsmodExtension = '.ttsmod';
