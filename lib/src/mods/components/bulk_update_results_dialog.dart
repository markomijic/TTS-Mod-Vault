import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart'
    show HookConsumerWidget, WidgetRef;
import 'package:tts_mod_vault/src/state/bulk_actions/mod_update_result.dart'
    show ModUpdateResult, ModUpdateStatus;

class BulkUpdateResultsDialog extends HookConsumerWidget {
  final List<ModUpdateResult> results;
  final bool wasCancelled;

  const BulkUpdateResultsDialog({
    super.key,
    required this.results,
    this.wasCancelled = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Categorize results
    final updated =
        results.where((r) => r.status == ModUpdateStatus.updated).toList();
    final upToDate =
        results.where((r) => r.status == ModUpdateStatus.upToDate).toList();
    final failed =
        results.where((r) => r.status == ModUpdateStatus.failed).toList();

    return BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 2, sigmaY: 2),
      child: AlertDialog(
        title: Row(
          children: [
            Icon(
              wasCancelled ? Icons.warning : Icons.check_circle,
              color: wasCancelled ? Colors.orange : Colors.green,
            ),
            const SizedBox(width: 8),
            Text(wasCancelled ? 'Update Cancelled' : 'Update Complete'),
          ],
        ),
        content: SizedBox(
          width: 700,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Summary counts
              _buildSummary(updated.length, upToDate.length, failed.length),

              const SizedBox(height: 16),

              // Scrollable list of mods
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (updated.isNotEmpty)
                        _buildSection(
                          'Updated',
                          updated,
                          Colors.green,
                          Icons.check_circle,
                        ),
                      if (upToDate.isNotEmpty)
                        _buildSection(
                          'Already Up to Date',
                          upToDate,
                          Colors.blue,
                          Icons.info,
                        ),
                      if (failed.isNotEmpty)
                        _buildSection(
                          'Failed',
                          failed,
                          Colors.red,
                          Icons.error,
                        ),
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
        ],
      ),
    );
  }

  Widget _buildSummary(int updatedCount, int upToDateCount, int failedCount) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildSummaryItem('Updated', updatedCount, Colors.green),
          _buildSummaryItem('Up to Date', upToDateCount, Colors.blue),
          _buildSummaryItem('Failed', failedCount, Colors.red),
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

  Widget _buildSection(
    String title,
    List<ModUpdateResult> items,
    Color color,
    IconData icon,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),
        Row(
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(width: 8),
            Text(
              '$title (${items.length})',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ...items.map((result) => _buildModItem(result, color)),
      ],
    );
  }

  Widget _buildModItem(ModUpdateResult result, Color color) {
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  result.modName,
                  style: const TextStyle(fontSize: 14),
                ),
                if (result.errorMessage != null)
                  Text(
                    result.errorMessage!,
                    style: const TextStyle(
                      fontSize: 12,
                      color: Colors.white70,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
