// A three-template source `Mods` folder for the tool tests.
import 'dart:io';

import 'package:path/path.dart' as p;

/// Writes `Mods/Workshop/111.json`, `Mods/Workshop/333.json`,
/// `Mods/Workshop/Sub/222.json` and a `WorkshopFileInfos.json` (which the
/// generator must skip) under [root] and returns the `Mods` path.
///
/// URL counts per template: 111 has 5 scheme URLs (one legacy-host, one
/// multi-language value that splits in two, one with a query), 222 has 3,
/// 333 has one scheme URL and one scheme-less value.
String writeStressSource(Directory root) {
  final mods = p.join(root.path, 'Mods');
  final sub = Directory(p.join(mods, 'Workshop', 'Sub'))
    ..createSync(recursive: true);
  File(p.join(mods, 'Workshop', '111.json')).writeAsStringSync(
    '{"SaveName":"Alpha","EpochTime":1700000000,"ObjectStates":['
    '{"Name":"Custom_Model","CustomMesh":{'
    '"MeshURL":"https://steamusercontent-a.akamaihd.net/ugc/1/A/",'
    '"DiffuseURL":"http://cloud-3.steamusercontent.com/ugc/2/B/"}},'
    '{"Name":"Custom_Tile","CustomImage":{'
    '"ImageURL":"{en}https://x.example/en.png{fr}https://x.example/fr.png"}},'
    '{"Name":"Custom_PDF","CustomPDF":{"PDFUrl":"https://docs.example/a.pdf?x=1"}}'
    ']}',
  );
  File(p.join(sub.path, '222.json')).writeAsStringSync(
    '{"SaveName":"Beta","EpochTime":1600000000,"ObjectStates":['
    '{"Name":"Custom_Token","CustomImage":{"ImageURL":"https://img.example/t.png"}},'
    '{"Name":"Bundle","CustomAssetbundle":{"AssetbundleURL":"https://ab.example/x.unity3d"}},'
    '{"Name":"Audio","CustomAudio":{"CurrentAudioURL":"https://snd.example/s.mp3"}}'
    ']}',
  );
  File(p.join(mods, 'Workshop', '333.json')).writeAsStringSync(
    '{"SaveName":"Gamma","ObjectStates":[{"Name":"Custom_Tile","CustomImage":{'
    '"ImageURL":"www.noscheme.example/img.png",'
    '"BackURL":"https://img.example/back.jpg"}}]}',
  );
  File(p.join(mods, 'Workshop', 'WorkshopFileInfos.json'))
      .writeAsStringSync('{"not":"a mod"}');
  return mods;
}
