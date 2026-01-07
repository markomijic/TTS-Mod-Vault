import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:tts_mod_vault/src/models/log_entry.dart';

class LogLineItem extends StatelessWidget {
  final LogEntry entry;

  const LogLineItem({
    super.key,
    required this.entry,
  });

  Future<void> _copyToClipboard(BuildContext context) async {
    await Clipboard.setData(ClipboardData(text: entry.fullLogLine));

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Copied to clipboard'),
          duration: Duration(seconds: 1),
          behavior: SnackBarBehavior.floating,
          width: 200,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0, horizontal: 12.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Timestamp
          SizedBox(
            width: 80,
            child: Text(
              entry.formattedTimestamp,
              style: TextStyle(
                fontSize: 11.7,
                color: Colors.grey.shade400,
                fontFamily: 'monospace',
              ),
            ),
          ),
          const SizedBox(width: 12),
          // Message
          Expanded(
            child: SelectableText(
              entry.message,
              style: TextStyle(
                fontSize: 14,
                color: entry.color,
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Copy button
          MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              onTap: () => _copyToClipboard(context),
              child: Icon(
                Icons.content_copy,
                size: 16,
                color: Colors.grey.shade500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
