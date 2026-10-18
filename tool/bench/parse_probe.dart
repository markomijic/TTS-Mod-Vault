// Times the pieces of `JsonModReader.readFull` on one mod JSON, so the
// parse critical path (one big file on one worker) can be attributed to
// reading, decoding or URL extraction. Read-only; pass the JSON path.
//
//   dart compile exe tool/bench/parse_probe.dart -o <out>/parse_probe.exe
//   parse_probe.exe "<path to mod>.json" [repeats]
import 'dart:convert';
import 'dart:io';

import 'package:tts_mod_vault/domain/enums/mod_type.dart';
import 'package:tts_mod_vault/domain/parsing/json_mod_reader.dart';
import 'package:tts_mod_vault/domain/parsing/url_extraction.dart';

Future<void> main(List<String> args) async {
  final path = args.first;
  final repeats = args.length > 1 ? int.parse(args[1]) : 3;
  final file = File(path);
  stdout.writeln('$path: ${file.lengthSync()} bytes');
  for (var i = 0; i < repeats; i++) {
    final sw = Stopwatch()..start();
    final bytes = await file.readAsBytes();
    final tBytes = sw.elapsedMilliseconds;
    sw.reset();
    final text = utf8.decode(bytes);
    final tDecode = sw.elapsedMilliseconds;
    sw.reset();
    final text2 = await file.readAsString();
    final tString = sw.elapsedMilliseconds;
    sw.reset();
    final latin = latin1.decode(bytes);
    final tLatin = sw.elapsedMilliseconds;
    sw.reset();
    final urls = extractAssetUrls(text);
    final tExtract = sw.elapsedMilliseconds;
    sw.reset();
    final typed = extractAssetUrlsTyped(text2);
    final tTyped = sw.elapsedMilliseconds;
    sw.reset();
    final full = await const JsonModReader().readFull(path, ModType.mod);
    final tFull = sw.elapsedMilliseconds;
    sw.reset();
    final fromBytes = extractAssetUrlsFromBytes(bytes);
    final tBytesScan = sw.elapsedMilliseconds;
    final same =
        fromBytes.length == urls.length &&
        fromBytes.entries.every((e) => urls[e.key] == e.value);
    stdout.writeln(
      'run $i: readAsBytes=${tBytes}ms utf8.decode=${tDecode}ms '
      'readAsString=${tString}ms latin1=${tLatin}ms '
      'extract=${tExtract}ms (${urls.length} urls) typed=${tTyped}ms '
      '(${typed.length}) readFull=${tFull}ms (${full.assets.length}) '
      'bytesScan=${tBytesScan}ms (${fromBytes.length}, same=$same) '
      'chars=${text.length} latinLen=${latin.length}',
    );
  }
}
