import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart' show useState;
import 'package:hooks_riverpod/hooks_riverpod.dart'
    show HookConsumerWidget, WidgetRef;
import 'package:tts_mod_vault/src/state/bulk_actions/mod_url_check_result.dart'
    show ModUrlCheckResult;
import 'package:tts_mod_vault/src/utils.dart' show copyToClipboard;

class BulkUrlCheckResultsDialog extends HookConsumerWidget {
  final List<ModUrlCheckResult> results;
  final bool wasCancelled;

  const BulkUrlCheckResultsDialog({
    super.key,
    required this.results,
    this.wasCancelled = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final modsWithInvalid =
        results.where((r) => r.invalidUrls.isNotEmpty).toList();
    final totalInvalid =
        modsWithInvalid.fold<int>(0, (acc, r) => acc + r.invalidUrls.length);
    final checkedCount = results.where((r) => !r.cancelled).length;

    return BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 2, sigmaY: 2),
      child: AlertDialog(
        title: Row(
          children: [
            Icon(
              wasCancelled ? Icons.warning_amber_rounded : Icons.check_circle,
              color: wasCancelled ? Colors.orange : Colors.green,
            ),
            const SizedBox(width: 8),
            Text(wasCancelled ? 'URL Check Cancelled' : 'URL Check Complete'),
          ],
        ),
        content: SizedBox(
          width: 1000,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildSummary(modsWithInvalid.length, totalInvalid, checkedCount),
              const SizedBox(height: 16),
              if (modsWithInvalid.isEmpty)
                const Text(
                  'All URLs are valid',
                  style: TextStyle(fontSize: 16),
                )
              else
                Flexible(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ...modsWithInvalid.map((r) => _ModSection(result: r)),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
          if (modsWithInvalid.isNotEmpty)
            ElevatedButton.icon(
              onPressed: () {
                final text = modsWithInvalid
                    .map((r) => '${r.modName}\n${r.invalidUrls.join('\n')}')
                    .join('\n\n');
                copyToClipboard(context, text, showSnackBarAfterCopying: false);
              },
              icon: const Icon(Icons.copy_all),
              label: const Text('Copy all invalid URLs'),
            ),
        ],
      ),
    );
  }

  Widget _buildSummary(
      int modsWithInvalidCount, int totalInvalidCount, int checkedCount) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildSummaryItem('Mods with invalid URLs', modsWithInvalidCount,
              totalInvalidCount > 0 ? Colors.red : Colors.green),
          _buildSummaryItem('Invalid URLs', totalInvalidCount,
              totalInvalidCount > 0 ? Colors.red : Colors.green),
          _buildSummaryItem('Mods checked', checkedCount, Colors.blue),
        ],
      ),
    );
  }

  Widget _buildSummaryItem(String label, int count, Color color) {
    return Column(
      children: [
        Text(
          count.toString(),
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        Text(label),
      ],
    );
  }
}

class _ModSection extends HookConsumerWidget {
  final ModUrlCheckResult result;

  const _ModSection({required this.result});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isExpanded = useState(false);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),
        MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => isExpanded.value = !isExpanded.value,
            child: Row(
              children: [
                Icon(
                  isExpanded.value
                      ? Icons.keyboard_arrow_down
                      : Icons.keyboard_arrow_right,
                  color: Colors.red,
                  size: 22,
                ),
                const SizedBox(width: 4),
                const Icon(Icons.error, color: Colors.red, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${result.modName} (${result.invalidUrls.length})',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.red,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (isExpanded.value) ...[
          const SizedBox(height: 4),
          ...result.invalidUrls.asMap().entries.map(
                (e) => _InvalidUrlRow(url: e.value, index: e.key),
              ),
        ],
      ],
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
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: MouseRegion(
        onEnter: (_) => isHovered.value = true,
        onExit: (_) => isHovered.value = false,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '${index + 1}. ',
              style: const TextStyle(fontSize: 15),
            ),
            Expanded(
              child: Text(
                url,
                style: TextStyle(
                    fontSize: 15,
                    backgroundColor: isHovered.value
                        ? Colors.grey[850]
                        : Colors.transparent),
              ),
            ),
            IconButton(
              iconSize: 16,
              padding: EdgeInsets.zero,
              mouseCursor: SystemMouseCursors.click,
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
