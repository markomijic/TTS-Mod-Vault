import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:tts_mod_vault/src/state/logging/logging_state.dart';
import 'package:tts_mod_vault/src/state/provider.dart' show loggingProvider;

class LoggingConsole extends HookConsumerWidget {
  const LoggingConsole({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final loggingState = ref.watch(loggingProvider);
    final loggingNotifier = ref.read(loggingProvider.notifier);
    final scrollController = useScrollController();
    final filterController = useTextEditingController();

    // Auto-scroll to bottom when new logs are added
    useEffect(() {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (scrollController.hasClients) {
          scrollController.animateTo(
            scrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 100),
            curve: Curves.easeOut,
          );
        }
      });
      return null;
    }, [loggingState.entries.length]);

    if (!loggingState.isVisible) {
      return const SizedBox.shrink();
    }

    return Container(
      height: 400,
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.9),
        border: Border.all(color: Colors.grey.shade600),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
      ),
      child: Column(
        children: [
          // Header with controls
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.grey.shade800,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
            ),
            child: Row(
              children: [
                const Icon(Icons.terminal, color: Colors.white, size: 16),
                const SizedBox(width: 8),
                const Text(
                  'Debug Console',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
                const Spacer(),
                // Level filter buttons
                Wrap(
                  spacing: 4,
                  children: LogLevel.values.map((level) {
                    final isActive = loggingState.visibleLevels.contains(level);
                    return FilterChip(
                      label: Text(
                        level.name.toUpperCase(),
                        style: TextStyle(
                          color: isActive ? Colors.black : Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      selected: isActive,
                      onSelected: (selected) {
                        final newLevels = Set<LogLevel>.from(loggingState.visibleLevels);
                        if (selected) {
                          newLevels.add(level);
                        } else {
                          newLevels.remove(level);
                        }
                        loggingNotifier.setVisibleLevels(newLevels);
                      },
                      backgroundColor: Colors.transparent,
                      selectedColor: _getLevelColor(level),
                      side: BorderSide(color: _getLevelColor(level), width: 1),
                    );
                  }).toList(),
                ),
                const SizedBox(width: 8),
                // Action buttons
                IconButton(
                  icon: const Icon(Icons.copy, color: Colors.white, size: 16),
                  onPressed: () => _copyLogsToClipboard(loggingState),
                  tooltip: 'Copy logs to clipboard',
                ),
                IconButton(
                  icon: const Icon(Icons.clear, color: Colors.white, size: 16),
                  onPressed: loggingNotifier.clearLogs,
                  tooltip: 'Clear logs',
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white, size: 16),
                  onPressed: loggingNotifier.toggleVisibility,
                  tooltip: 'Close console',
                ),
              ],
            ),
          ),
          // Filter bar
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.grey.shade900,
            ),
            child: TextField(
              controller: filterController,
              style: const TextStyle(color: Colors.white, fontSize: 12),
              decoration: const InputDecoration(
                hintText: 'Filter logs...',
                hintStyle: TextStyle(color: Colors.grey),
                prefixIcon: Icon(Icons.search, color: Colors.grey, size: 16),
                border: InputBorder.none,
                contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              ),
              onChanged: loggingNotifier.setFilter,
            ),
          ),
          // Log entries
          Expanded(
            child: ListView.builder(
              controller: scrollController,
              itemCount: loggingState.filteredEntries.length,
              itemBuilder: (context, index) {
                final entry = loggingState.filteredEntries[index];
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Timestamp
                      Text(
                        entry.formattedTime,
                        style: const TextStyle(
                          color: Colors.grey,
                          fontSize: 10,
                          fontFamily: 'monospace',
                        ),
                      ),
                      const SizedBox(width: 8),
                      // Level badge
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                        decoration: BoxDecoration(
                          color: entry.color,
                          borderRadius: BorderRadius.circular(3),
                        ),
                        child: Text(
                          entry.levelText,
                          style: const TextStyle(
                            color: Colors.black,
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      // Category
                      if (entry.category != null) ...[
                        Text(
                          '[${entry.category}]',
                          style: const TextStyle(
                            color: Colors.cyan,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(width: 4),
                      ],
                      // Message
                      Expanded(
                        child: Text(
                          entry.message,
                          style: TextStyle(
                            color: entry.color,
                            fontSize: 11,
                            fontFamily: 'monospace',
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
          // Status bar
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: Colors.grey.shade800,
            ),
            child: Row(
              children: [
                Text(
                  '${loggingState.filteredEntries.length} / ${loggingState.entries.length} entries',
                  style: const TextStyle(color: Colors.grey, fontSize: 10),
                ),
                const Spacer(),
                if (loggingState.filterText != null && loggingState.filterText!.isNotEmpty)
                  Text(
                    'Filtered by: "${loggingState.filterText}"',
                    style: const TextStyle(color: Colors.yellow, fontSize: 10),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Color _getLevelColor(LogLevel level) {
    switch (level) {
      case LogLevel.info:
        return Colors.green;
      case LogLevel.warning:
        return Colors.orange;
      case LogLevel.error:
        return Colors.red;
      case LogLevel.debug:
        return Colors.grey;
      case LogLevel.network:
        return Colors.blue;
    }
  }

  void _copyLogsToClipboard(LoggingState loggingState) {
    final logs = loggingState.filteredEntries.map((e) => e.toString()).join('\n');
    Clipboard.setData(ClipboardData(text: logs));
  }
}

class LoggingToggleButton extends ConsumerWidget {
  const LoggingToggleButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final loggingState = ref.watch(loggingProvider);
    final loggingNotifier = ref.read(loggingProvider.notifier);

    return IconButton(
      icon: Icon(
        Icons.terminal,
        color: loggingState.isVisible ? Colors.cyan : Colors.grey,
      ),
      onPressed: loggingNotifier.toggleVisibility,
      tooltip: loggingState.isVisible ? 'Hide Debug Console' : 'Show Debug Console',
    );
  }
}
