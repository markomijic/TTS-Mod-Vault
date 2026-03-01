import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart'
    show HookConsumerWidget, WidgetRef;
import 'dart:ui' show ImageFilter;
import 'package:tts_mod_vault/src/state/mods/mod_model.dart' show Mod;
import 'package:tts_mod_vault/src/state/provider.dart'
    show downloadProvider, selectedModProvider;
import 'package:tts_mod_vault/src/utils.dart' show copyToClipboard;

class UrlCheckResultsDialog extends HookConsumerWidget {
  final Mod mod;

  const UrlCheckResultsDialog({super.key, required this.mod});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedMod = ref.watch(selectedModProvider) ?? mod;
    final downloadNotifier = ref.watch(downloadProvider.notifier);
    final downloadState = ref.watch(downloadProvider);

    final invalidUrls = useMemoized(
        () => selectedMod.invalidUrls ?? [], [selectedMod.invalidUrls]);
    final isChecking = useState(mod.invalidUrls == null);
    final cancelRequested = useRef(false);

    useEffect(() {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mod.invalidUrls == null) {
          final navigator = Navigator.of(context);
          ref.read(downloadProvider.notifier).checkModUrlsLive(mod).then((_) {
            if (cancelRequested.value) {
              navigator.pop();
            } else {
              isChecking.value = false;
            }
          });
        }
      });

      return null;
    }, []);

    return PopScope(
      canPop: !isChecking.value,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 2, sigmaY: 2),
        child: AlertDialog(
          title: SizedBox(
              width: 1000,
              child:
                  Text(selectedMod.saveName, style: TextStyle(fontSize: 18))),
          content: SizedBox(
            width: 1000,
            child: isChecking.value
                ? Column(
                    spacing: 12,
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        downloadState.statusMessage ?? 'Checking URLs...',
                        style: const TextStyle(fontSize: 16),
                      ),
                      LinearProgressIndicator(
                        minHeight: 24,
                        backgroundColor: Colors.grey.shade300,
                        color: Colors.green,
                        borderRadius: BorderRadius.all(Radius.circular(32)),
                        value: downloadState.progress,
                      ),
                    ],
                  )
                : Column(
                    spacing: 16,
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        invalidUrls.isNotEmpty
                            ? 'Invalid URLs: ${invalidUrls.length}'
                            : 'All URLs are valid',
                        style: TextStyle(
                          color: invalidUrls.isNotEmpty
                              ? Colors.red
                              : Colors.white,
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
              onPressed: () {
                if (isChecking.value) {
                  cancelRequested.value = true;
                  downloadNotifier.cancelAllDownloads();
                } else {
                  Navigator.of(context).pop();
                }
              },
              child: Text(isChecking.value ? 'Cancel' : 'Close'),
            ),
            if (!isChecking.value) ...[
              ElevatedButton.icon(
                onPressed: () {
                  cancelRequested.value = false;
                  isChecking.value = true;
                  final navigator = Navigator.of(context);
                  ref
                      .read(downloadProvider.notifier)
                      .checkModUrlsLive(selectedMod)
                      .then((_) {
                    if (cancelRequested.value) {
                      navigator.pop();
                    } else {
                      isChecking.value = false;
                    }
                  });
                },
                icon: const Icon(Icons.refresh),
                label: const Text('Re-check'),
              ),
              if (invalidUrls.isNotEmpty)
                ElevatedButton.icon(
                  onPressed: () {
                    final invalidUrlsText = invalidUrls.join('\n');
                    copyToClipboard(context, invalidUrlsText,
                        showSnackBarAfterCopying: false);
                  },
                  icon: const Icon(Icons.copy_all),
                  label: const Text('Copy all invalid URLs'),
                ),
            ],
          ],
        ),
      ),
    );
  }
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
