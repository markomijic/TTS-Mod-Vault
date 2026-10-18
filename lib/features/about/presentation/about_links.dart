/// External links of the About tab and the update notice, plus the URL
/// opener they share (so tests can swap `url_launcher` out).
library;

import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:url_launcher/url_launcher.dart' show launchUrl;

/// The Nexus Mods page of the app (v2 `nexusModsDownloadPageUrl`).
const String nexusModsDownloadPageUrl =
    'https://www.nexusmods.com/tabletopsimulator/mods/426';

/// The Steam "Help & Feedback" discussion thread (v2 `steamDiscussionUrl`).
const String steamDiscussionUrl =
    'https://steamcommunity.com/app/286160/discussions/0/591772542952298985/';

/// The Ko-fi page (v2 `kofiUrl`).
const String kofiUrl = 'https://ko-fi.com/ttsmodvault';

/// The GitHub releases list.
const String gitHubReleasesUrl =
    'https://github.com/markomijic/TTS-Mod-Vault/releases';

/// The GitHub release page of [version] (v2 `getGitHubReleaseUrl`).
String gitHubReleaseUrl(String version) => '$gitHubReleasesUrl/tag/v$version';

/// Opens [url] in the default browser; returns false when that failed.
typedef UrlOpener = Future<bool> Function(Uri url);

/// The URL opener used by the About tab and the update notice; defaults to
/// `url_launcher`'s [launchUrl] and is overridden in tests.
final urlOpenerProvider = Provider<UrlOpener>((_) => launchUrl);
