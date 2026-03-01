import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:tts_mod_vault/src/state/mods/mod_model.dart' show ModTypeEnum;

/// Returns "This asset is shared with X mods, Y saves."
String buildSharedAssetSummary(Map<ModTypeEnum, List<String>> sharingMods) {
  final summaryParts = <String>[];
  for (final type in ModTypeEnum.values) {
    final names = sharingMods[type];
    if (names == null || names.isEmpty) continue;
    summaryParts
        .add('${names.length} ${type.label}${names.length > 1 ? "s" : ""}');
  }
  return 'This asset is shared with ${summaryParts.join(", ")}.';
}

/// Formats sharing info as "This asset is shared with X mods, Y saves.\n\nMods:\n..."
String buildSharedAssetText(Map<ModTypeEnum, List<String>> sharingMods) {
  final detailParts = <String>[];
  for (final type in ModTypeEnum.values) {
    final names = sharingMods[type];
    if (names == null || names.isEmpty) continue;
    detailParts.add(
        '${type.label[0].toUpperCase()}${type.label.substring(1)}s:\n${names.join("\n")}');
  }
  return '${buildSharedAssetSummary(sharingMods)}\n\n${detailParts.join("\n\n")}';
}

/// Shows an AlertDialog listing all mods/saves that share the asset.
void showSharedAssetDialog(
    BuildContext context, Map<ModTypeEnum, List<String>> sharingMods) {
  showDialog<void>(
    context: context,
    builder: (context) => BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 2, sigmaY: 2),
      child: AlertDialog(
        title: const Text('Shared Asset'),
        content: SingleChildScrollView(
          child: SelectableText(
            buildSharedAssetText(sharingMods),
            selectionColor: Colors.grey[850],
          ),
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    ),
  );
}
