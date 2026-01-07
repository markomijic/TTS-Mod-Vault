import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:tts_mod_vault/src/mods/components/log_line_item.dart';
import 'package:tts_mod_vault/src/providers/log_provider.dart';

class LogPanel extends HookConsumerWidget {
  final double height;

  const LogPanel({
    super.key,
    this.height = 300,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isExpanded = useState(false);
    final searchQuery = useState('');
    final scrollController = useScrollController();

    // Watch filtered logs
    final logs = ref.watch(filteredLogProvider(searchQuery.value));

    // Auto-scroll to bottom when new logs are added
    useEffect(() {
      if (isExpanded.value && logs.isNotEmpty) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (scrollController.hasClients) {
            scrollController.animateTo(
              scrollController.position.maxScrollExtent,
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOut,
            );
          }
        });
      }
      return null;
    }, [logs.length]);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      height: isExpanded.value ? height : 20,
      /*  decoration: BoxDecoration(
        color: Colors.grey[900],
        /*  border: const Border(
          top: BorderSide(color: Colors.white, width: 1),
        ), */
      ), */
      child: Column(
        children: [
          // Header
          MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              onTap: () => isExpanded.value = !isExpanded.value,
              child: Container(
                height: 20,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  children: [
                    // Title
                    if (isExpanded.value)
                      const Text(
                        'Logs',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                          color: Colors.white,
                        ),
                      ),
                    if (isExpanded.value) const SizedBox(width: 16),
                    // Search field
                    if (isExpanded.value) ...[
                      SizedBox(
                        width: 300,
                        height: 32,
                        child: TextField(
                          onChanged: (value) => searchQuery.value = value,
                          style: const TextStyle(
                              fontSize: 14, color: Colors.white),
                          decoration: InputDecoration(
                            hintText: 'Filter logs...',
                            hintStyle: TextStyle(
                              fontSize: 14,
                              color: Colors.white.withValues(alpha: 0.6),
                            ),
                            prefixIcon: const Icon(Icons.search,
                                size: 18, color: Colors.white),
                            filled: true,
                            fillColor: Colors.black87,
                            contentPadding:
                                const EdgeInsets.symmetric(vertical: 4),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(4),
                              borderSide: BorderSide.none,
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(4),
                              borderSide: BorderSide.none,
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(4),
                              borderSide: const BorderSide(
                                  color: Colors.white, width: 1),
                            ),
                          ),
                        ),
                      ),
                    ],
                    const Spacer(),
                    // Clear button
                    if (isExpanded.value && logs.isNotEmpty) ...[
                      MouseRegion(
                        cursor: SystemMouseCursors.click,
                        child: GestureDetector(
                          onTap: () {
                            ref.read(logProvider.notifier).clear();
                            searchQuery.value = '';
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: Colors.red.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(color: Colors.red, width: 1),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.clear_all,
                                    size: 16, color: Colors.red),
                                SizedBox(width: 4),
                                Text(
                                  'Clear',
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: Colors.red,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                    ],
                    // Collapse/expand toggle
                    Icon(
                      isExpanded.value
                          ? Icons.keyboard_arrow_down
                          : Icons.keyboard_arrow_up,
                      color: Colors.white,
                      size: 16,
                    ),
                  ],
                ),
              ),
            ),
          ),
          // Log content
          if (isExpanded.value)
            Expanded(
              child: logs.isEmpty
                  ? Center(
                      child: Text(
                        searchQuery.value.isEmpty
                            ? 'No logs yet'
                            : 'No logs match your filter',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    )
                  : ListView.builder(
                      controller: scrollController,
                      itemCount: logs.length,
                      itemBuilder: (context, index) {
                        return LogLineItem(entry: logs[index]);
                      },
                    ),
            ),
        ],
      ),
    );
  }
}
