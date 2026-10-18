// Stress library generator (docs/v3-rewrite-plan.md, section 10.4).
//
// Copies the Workshop JSONs found under a source `Mods` folder N times with
// new numeric ids and rewritten asset URLs (so every copy has its own file
// keys), writes 1 KB placeholder asset files for a fraction of the URLs and
// creates the empty `Saves/` tree, so the result is a TTS library the app
// can point at:
//
//   dart run tool/stress_library.dart --source <real Mods dir> --out <dir>
//       --mods 2000 --present-fraction 0.6 [--seed 1] [--max-template-mb 0]
//
// Safety (plan 10.2): the source is only read. The output folder may not be
// inside the user's Documents folder (where the real library lives) nor
// inside the source. Only `dart run` is needed (no Flutter, no native
// assets), so this also AOT-compiles with `dart compile exe`.
import 'dart:io';
import 'dart:math' show Random;

import 'package:file/local.dart';
import 'package:path/path.dart' as p;
import 'package:tts_mod_vault/data/fs/mod_file_scanner.dart';
import 'package:tts_mod_vault/domain/constants.dart';
import 'package:tts_mod_vault/domain/enums/asset_type.dart';
import 'package:tts_mod_vault/domain/enums/mod_type.dart';
import 'package:tts_mod_vault/domain/parsing/asset_extension.dart';
import 'package:tts_mod_vault/domain/parsing/url_extraction.dart';
import 'package:tts_mod_vault/domain/rules/file_key.dart';

/// Size of every placeholder asset file.
const int placeholderBytes = 1024;

/// First id given to a generated mod; copy `i` becomes `<firstId + i>.json`.
const int firstGeneratedId = 9000000000;

/// What [generateStressLibrary] produced.
final class StressLibrarySummary {
  /// Creates a summary.
  const StressLibrarySummary({
    required this.outDir,
    required this.templates,
    required this.mods,
    required this.urls,
    required this.urlsNotRewritten,
    required this.placeholderFiles,
    required this.bytesWritten,
    required this.elapsed,
  });

  /// The generated library root (contains `Mods/` and `Saves/`).
  final String outDir;

  /// Source JSONs the copies were made from.
  final int templates;

  /// Mod JSONs written.
  final int mods;

  /// Asset URLs rewritten across every copy (one key per URL per copy).
  final int urls;

  /// Asset URLs the extractor found but that could not be located verbatim
  /// in the text (scheme-less or `\r\n`-laden values); they are left as
  /// they are and therefore shared between copies.
  final int urlsNotRewritten;

  /// Placeholder asset files written.
  final int placeholderFiles;

  /// Bytes written (JSONs plus placeholders).
  final int bytesWritten;

  /// Wall time of the generation.
  final Duration elapsed;

  @override
  String toString() =>
      'templates=$templates mods=$mods urls=$urls '
      'urlsNotRewritten=$urlsNotRewritten placeholderFiles=$placeholderFiles '
      'bytesWritten=$bytesWritten elapsedMs=${elapsed.inMilliseconds}';
}

/// Rewrites [url] for copy [copy] so its file key differs from every other
/// copy's. A query parameter keeps the URL a URL and gives
/// `fileNameFromUrl` a distinct suffix (`...c17`).
String rewriteUrlForCopy(String url, int copy) =>
    url.contains('?') ? '$url&c$copy' : '$url?c$copy';

// Anything with a scheme up to a `{`, `}`, `"` or `\`: the shape of the
// values `extractAssetUrls` splits multi-language values into. Scheme-less
// values and values with literal `\r\n` inside are not matched and stay as
// they are (counted in `urlsNotRewritten`).
final _schemeUrl = RegExp(r'[a-zA-Z][a-zA-Z0-9+.-]*://[^{}"\\]+');

/// Rewrites every asset URL of [text] (the URLs `extractAssetUrlsTyped`
/// finds) with [rewriteUrlForCopy] in one pass and returns the new text,
/// the rewritten URLs with their types and how many extracted URLs were not
/// found verbatim.
({String text, List<AssetUrl> rewritten, int notRewritten}) rewriteModText(
  String text,
  int copy,
) {
  // Legacy-host URLs are extracted in their normalised form; normalise the
  // text first so the one-pass replacement below finds them.
  final normalized = text.replaceAll(oldCloudUrl, newSteamUserContentUrl);
  final assets = extractAssetUrlsTyped(normalized);
  final byUrl = {for (final asset in assets) asset.url: asset};
  final found = <String>{};
  final out = normalized.replaceAllMapped(_schemeUrl, (match) {
    final url = match.group(0)!;
    final asset = byUrl[url];
    if (asset == null) return url;
    found.add(url);
    return rewriteUrlForCopy(url, copy);
  });
  final rewritten = [
    for (final asset in assets)
      if (found.contains(asset.url))
        AssetUrl(
          url: rewriteUrlForCopy(asset.url, copy),
          jsonKey: asset.jsonKey,
          type: asset.type,
        ),
  ];
  return (
    text: out,
    rewritten: rewritten,
    notRewritten: assets.length - found.length,
  );
}

/// The roots a stress library must never be written into: the user's
/// Documents folder (the real TTS library and the 2.x data live there).
List<String> defaultForbiddenRoots() {
  final env = Platform.environment;
  final homes = <String>{?env['USERPROFILE'], ?env['HOME']};
  return [for (final home in homes) p.join(home, 'Documents')];
}

bool _isInside(String path, String root) {
  final a = p.normalize(p.absolute(path)).toLowerCase();
  final b = p.normalize(p.absolute(root)).toLowerCase();
  return a == b || p.isWithin(b, a);
}

/// Generates the library. [sourceModsDir] is a TTS `Mods` folder whose
/// `Workshop/` sub-tree supplies the templates (recursively; the TTS index
/// files are skipped); [outDir] receives `Mods/Workshop/<id>.json`, the
/// placeholder files under `Mods/<asset folder>/` and an empty `Saves/`
/// tree. [mods] copies are made round-robin over the templates; for each
/// copy exactly `round(urls * presentFraction)` of its rewritten URLs get a
/// placeholder file, chosen with [seed]. Templates larger than
/// [maxTemplateBytes] are skipped when that is positive.
///
/// Throws [ArgumentError] when [outDir] lies inside one of [forbiddenRoots]
/// (default: the user's Documents folder) or inside [sourceModsDir], or when
/// the source has no templates.
Future<StressLibrarySummary> generateStressLibrary({
  required String sourceModsDir,
  required String outDir,
  required int mods,
  required double presentFraction,
  int seed = 1,
  int maxTemplateBytes = 0,
  List<String>? forbiddenRoots,
  void Function(String line)? log,
}) async {
  final stopwatch = Stopwatch()..start();
  void say(String line) => log?.call(line);

  if (mods < 1) throw ArgumentError.value(mods, 'mods', 'must be >= 1');
  if (presentFraction < 0 || presentFraction > 1) {
    throw ArgumentError.value(
      presentFraction,
      'presentFraction',
      'must be in 0..1',
    );
  }
  for (final root in forbiddenRoots ?? defaultForbiddenRoots()) {
    if (_isInside(outDir, root)) {
      throw ArgumentError.value(
        outDir,
        'outDir',
        'refusing to write inside $root (plan 10.2: the real library is '
            'read-only)',
      );
    }
  }
  if (_isInside(outDir, sourceModsDir) || _isInside(sourceModsDir, outDir)) {
    throw ArgumentError.value(
      outDir,
      'outDir',
      'must not overlap the source folder $sourceModsDir',
    );
  }

  final scan = await scanModFilesWith(
    ModFileScanRequest(
      rootDir: p.join(sourceModsDir, ttsWorkshopFolder),
      type: ModType.mod,
    ),
    const LocalFileSystem(),
  );
  for (final warning in scan.warnings) {
    say('warning: $warning');
  }
  final templates = [
    for (final entry in scan.entries)
      if (maxTemplateBytes <= 0 || entry.sizeBytes <= maxTemplateBytes) entry,
  ]..sort((a, b) => a.jsonPath.compareTo(b.jsonPath));
  if (templates.isEmpty) {
    throw ArgumentError.value(
      sourceModsDir,
      'sourceModsDir',
      'no Workshop JSONs found under ${p.join(sourceModsDir, ttsWorkshopFolder)}',
    );
  }
  final templateBytes = templates.fold(0, (n, t) => n + t.sizeBytes);
  say(
    'templates: ${templates.length} JSONs, '
    '${(templateBytes / (1024 * 1024)).toStringAsFixed(1)} MB; '
    'estimated JSON output ~'
    '${(templateBytes / templates.length * mods / (1024 * 1024)).toStringAsFixed(0)} MB',
  );

  final root = Directory(outDir);
  await root.create(recursive: true);
  final workshopDir = Directory(
    p.join(outDir, ttsModsFolder, ttsWorkshopFolder),
  );
  await workshopDir.create(recursive: true);
  await Directory(p.join(outDir, ttsSavesFolder, ttsSavedObjectsFolder))
      .create(recursive: true);
  for (final type in AssetType.values) {
    await Directory(p.join(outDir, ttsModsFolder, type.folderName))
        .create(recursive: true);
    final raw = type.rawFolderName;
    if (raw != null) {
      await Directory(p.join(outDir, ttsModsFolder, raw)).create();
    }
  }

  final random = Random(seed);
  var urls = 0;
  var notRewritten = 0;
  var placeholders = 0;
  var bytes = 0;
  final placeholder = List<int>.filled(placeholderBytes, 0x20);
  // Cache the decoded templates: the same text is re-read for every copy
  // otherwise, and with 2,000 copies over ~100 templates that is 20x the
  // source size in reads.
  final texts = <String, String>{};

  for (var i = 0; i < mods; i++) {
    final template = templates[i % templates.length];
    final text = texts[template.jsonPath] ??= await File(template.jsonPath)
        .readAsString();
    final result = rewriteModText(text, i);
    urls += result.rewritten.length;
    notRewritten += result.notRewritten;

    final id = firstGeneratedId + i;
    final jsonFile = File(p.join(workshopDir.path, '$id.json'));
    await jsonFile.writeAsString(result.text);
    bytes += result.text.length;

    // Exactly round(n * fraction) of this copy's URLs get a file.
    final indexes = List<int>.generate(result.rewritten.length, (k) => k)
      ..shuffle(random);
    final present = (result.rewritten.length * presentFraction).round();
    final writes = <Future<void>>[];
    for (final k in indexes.take(present)) {
      final asset = result.rewritten[k];
      final path = p.join(
        outDir,
        ttsModsFolder,
        asset.type.folderName,
        '${fileNameFromUrl(asset.url)}${extensionForAsset(asset.type)}',
      );
      writes.add(File(path).writeAsBytes(placeholder));
      placeholders++;
      bytes += placeholderBytes;
      if (writes.length >= 64) {
        await Future.wait(writes);
        writes.clear();
      }
    }
    await Future.wait(writes);

    if ((i + 1) % 100 == 0 || i + 1 == mods) {
      say(
        'written ${i + 1}/$mods mods, $urls urls, $placeholders placeholder '
        'files, ${(bytes / (1024 * 1024)).toStringAsFixed(0)} MB, '
        '${stopwatch.elapsed.inSeconds}s',
      );
    }
  }
  // Templates with no usable URLs would still be fine; just report it.
  if (urls == 0) say('warning: no asset URLs were found in the templates');

  stopwatch.stop();
  return StressLibrarySummary(
    outDir: p.normalize(p.absolute(outDir)),
    templates: templates.length,
    mods: mods,
    urls: urls,
    urlsNotRewritten: notRewritten,
    placeholderFiles: placeholders,
    bytesWritten: bytes,
    elapsed: stopwatch.elapsed,
  );
}

const _usage = '''
usage: dart run tool/stress_library.dart --source <Mods dir> --out <dir>
           [--mods 2000] [--present-fraction 0.6] [--seed 1]
           [--max-template-mb 0]

  --source             a TTS "Mods" folder; its Workshop/ JSONs are the
                       templates (read only)
  --out                library root to create (gets Mods/ and Saves/); must
                       not be inside Documents or the source
  --mods               number of mod JSONs to generate (default 2000)
  --present-fraction   fraction of each mod's URLs that get a 1 KB
                       placeholder file (default 0.6)
  --seed               random seed for the present/missing choice (default 1)
  --max-template-mb    skip templates larger than this (default 0 = none)
''';

Future<void> main(List<String> args) async {
  String? source;
  String? out;
  var mods = 2000;
  var fraction = 0.6;
  var seed = 1;
  var maxTemplateMb = 0;
  for (var i = 0; i < args.length; i++) {
    final arg = args[i];
    String next() {
      if (i + 1 >= args.length) {
        stderr.writeln('missing value for $arg\n$_usage');
        exit(2);
      }
      return args[++i];
    }

    switch (arg) {
      case '--source':
        source = next();
      case '--out':
        out = next();
      case '--mods':
        mods = int.parse(next());
      case '--present-fraction':
        fraction = double.parse(next());
      case '--seed':
        seed = int.parse(next());
      case '--max-template-mb':
        maxTemplateMb = int.parse(next());
      case '-h' || '--help':
        stdout.write(_usage);
        return;
      default:
        stderr.writeln('unknown argument $arg\n$_usage');
        exit(2);
    }
  }
  if (source == null || out == null) {
    stderr.writeln('--source and --out are required\n$_usage');
    exit(2);
  }
  try {
    final summary = await generateStressLibrary(
      sourceModsDir: source,
      outDir: out,
      mods: mods,
      presentFraction: fraction,
      seed: seed,
      maxTemplateBytes: maxTemplateMb * 1024 * 1024,
      log: stdout.writeln,
    );
    stdout
      ..writeln('stress library: ${summary.outDir}')
      ..writeln(
        '  templates=${summary.templates} mods=${summary.mods} '
        'urls=${summary.urls} urlsNotRewritten=${summary.urlsNotRewritten}',
      )
      ..writeln(
        '  placeholderFiles=${summary.placeholderFiles} '
        'bytesWritten=${summary.bytesWritten} '
        '(${(summary.bytesWritten / (1024 * 1024)).toStringAsFixed(1)} MB) '
        'elapsedMs=${summary.elapsed.inMilliseconds}',
      );
  } on ArgumentError catch (error) {
    stderr.writeln(
      'error: ${error.message} (${error.name}: ${error.invalidValue})',
    );
    exit(1);
  }
}
