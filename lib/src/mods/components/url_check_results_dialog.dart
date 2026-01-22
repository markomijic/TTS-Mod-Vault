import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart'
    show HookConsumerWidget, WidgetRef;
import 'dart:ui' show ImageFilter;
import 'package:tts_mod_vault/src/state/mods/mod_model.dart' show Mod;
import 'package:tts_mod_vault/src/utils.dart' show copyToClipboard;

Widget buildUrlCheckResultsDialog(
  BuildContext context,
  List<String> invalidUrls,
  Mod mod,
) {
  return BackdropFilter(
    filter: ImageFilter.blur(sigmaX: 2, sigmaY: 2),
    child: AlertDialog(
      title: SizedBox(
          width: 1000,
          child: Text(mod.saveName, style: TextStyle(fontSize: 18))),
      content: SizedBox(
        width: 1000,
        child: Column(
          spacing: 16,
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              invalidUrls.isNotEmpty
                  ? 'Invalid URLs: ${invalidUrls.length}'
                  : 'All URLs are valid',
              style: TextStyle(
                color: invalidUrls.isNotEmpty ? Colors.red : Colors.white,
                fontSize: 16,
              ),
            ),
            if (invalidUrls.isNotEmpty)
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: invalidUrls.length,
                  itemBuilder: (context, index) {
                    final url = invalidUrls[index];
                    return _InvalidUrlRow(url: url, index: index);
                  },
                ),
              ),
          ],
        ),
      ),
      actions: [
        ElevatedButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
        if (invalidUrls.isNotEmpty)
          ElevatedButton.icon(
            onPressed: () {
              final invalidUrlsText = invalidUrls.join('\n');
              copyToClipboard(context, invalidUrlsText,
                  showSnackBarAfterCopying: false);
            },
            icon: Icon(Icons.copy_all),
            label: const Text('Copy all invalid URLs'),
          ),
      ],
    ),
  );
}

class _InvalidUrlRow extends HookConsumerWidget {
  final String url;
  final int index;

  const _InvalidUrlRow({required this.url, required this.index});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isHovered = useState(false);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: MouseRegion(
        onEnter: (_) => isHovered.value = true,
        onExit: (_) => isHovered.value = false,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '${index + 1}. ',
              style: TextStyle(fontSize: 16),
            ),
            Expanded(
              child: Text(
                url,
                style: TextStyle(
                    fontSize: 16,
                    backgroundColor: isHovered.value
                        ? Colors.grey[850]
                        : Colors.transparent),
              ),
            ),
            IconButton(
              iconSize: 16,
              padding: EdgeInsets.zero,
              onPressed: () => copyToClipboard(
                context,
                url,
                showSnackBarAfterCopying: false,
              ),
              icon: Icon(Icons.copy,
                  size: 16,
                  color: !isHovered.value ? Colors.transparent : Colors.white),
            ),
          ],
        ),
      ),
    );
  }
}
