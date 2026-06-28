import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart'
    show HookConsumerWidget, WidgetRef;
import 'dart:ui' show ImageFilter;
import 'package:tts_mod_vault/src/state/mods/mod_model.dart' show Mod;
import 'package:tts_mod_vault/src/state/provider.dart' show downloadProvider;
import 'package:tts_mod_vault/src/utils.dart' show copyToClipboard;

/// Entry point for the "Check for invalid URLs" action. If [mod] already has
/// cached results from a previous check, shows them immediately; otherwise runs
/// a fresh check first. Use the dialog's "Re-check" button (which calls
/// [runUrlCheckThenShowResults] directly) to force a fresh check.
void showUrlCheckResults(
  NavigatorState navigator,
  WidgetRef ref,
  Mod mod,
) {
  final cached = mod.invalidUrls;
  if (cached != null) {
    showDialog(
      context: navigator.context,
      builder: (_) => UrlCheckResultsDialog(mod: mod, invalidUrls: cached),
    );
    return;
  }

  runUrlCheckThenShowResults(navigator, ref, mod);
}

/// Runs a live URL check for [mod] (progress shows in the selected-mod view via
/// [UrlCheckProgressBar]) and then shows the results dialog — including when the
/// check was cancelled, displaying whatever partial findings were collected.
///
/// Pass a [NavigatorState] captured before the await (e.g. via
/// `Navigator.of(context, rootNavigator: true)`) so it stays valid across the
/// async gap and after any dialog pop.
Future<void> runUrlCheckThenShowResults(
  NavigatorState navigator,
  WidgetRef ref,
  Mod mod,
) async {
  final r = await ref.read(downloadProvider.notifier).checkModUrlsLive(mod);

  if (!navigator.mounted) return;

  showDialog(
    context: navigator.context,
    builder: (_) => UrlCheckResultsDialog(
      mod: mod,
      invalidUrls: r.invalidUrls,
      wasCancelled: r.cancelled,
    ),
  );
}

class UrlCheckResultsDialog extends HookConsumerWidget {
  final Mod mod;
  final List<String> invalidUrls;
  final bool wasCancelled;

  const UrlCheckResultsDialog({
    super.key,
    required this.mod,
    required this.invalidUrls,
    this.wasCancelled = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final String headingText;
    if (invalidUrls.isNotEmpty) {
      headingText = 'Invalid URLs: ${invalidUrls.length}';
    } else if (wasCancelled) {
      headingText = 'No invalid URLs found before cancelling';
    } else {
      headingText = 'All URLs are valid';
    }

    return BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 2, sigmaY: 2),
      child: AlertDialog(
        title: Row(
          children: [
            if (wasCancelled) ...[
              const Icon(Icons.warning_amber_rounded, color: Colors.orange),
              const SizedBox(width: 8),
            ],
            Expanded(
              child: Text(
                wasCancelled ? 'URL Check Cancelled' : mod.saveName,
                style: const TextStyle(fontSize: 18),
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: 1000,
          child: Column(
            spacing: 16,
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (wasCancelled)
                Text(
                  mod.saveName,
                  style: const TextStyle(fontSize: 16),
                ),
              Text(
                headingText,
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
          ElevatedButton.icon(
            onPressed: () {
              final navigator = Navigator.of(context, rootNavigator: true);
              navigator.pop();
              runUrlCheckThenShowResults(navigator, ref, mod);
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
