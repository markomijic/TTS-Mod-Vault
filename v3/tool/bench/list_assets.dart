// Prints the asset file keys of one or more mod JSONs, one per line as
// `<asset folder><TAB><file key>` (for example `Images<TAB>httpssteam...`),
// so `make_sandbox.ps1` can pick the cached files a mod needs out of the
// real library by case-insensitive basename match. Read-only; pure Dart
// (`dart run tool/bench/list_assets.dart --json <path> [--json <path2>]`).
import 'dart:io';

import 'package:tts_mod_vault/domain/parsing/url_extraction.dart';
import 'package:tts_mod_vault/domain/rules/file_key.dart';

Future<void> main(List<String> args) async {
  final paths = <String>[];
  for (var i = 0; i < args.length; i++) {
    if (args[i] == '--json') {
      if (i + 1 >= args.length) {
        stderr.writeln('--json needs a path');
        exit(2);
      }
      paths.add(args[++i]);
    } else {
      paths.add(args[i]);
    }
  }
  if (paths.isEmpty) {
    stderr.writeln(
      'usage: dart run tool/bench/list_assets.dart --json <mod.json> ...',
    );
    exit(2);
  }
  final seen = <String>{};
  for (final path in paths) {
    final file = File(path);
    if (!file.existsSync()) {
      stderr.writeln('not found: $path');
      exit(1);
    }
    final bytes = await file.readAsBytes();
    for (final asset in extractAssetUrlsTypedFromBytes(bytes)) {
      final key = fileKeyFromUrl(asset.url);
      if (seen.add('${asset.type.folderName}\t$key')) {
        stdout.writeln('${asset.type.folderName}\t$key');
      }
    }
  }
}
