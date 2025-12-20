import 'package:flutter/material.dart';
import 'package:tts_mod_vault/src/mods/components/components.dart'
    show CustomTooltip;

class HelpTooltip extends StatelessWidget {
  const HelpTooltip({super.key});

  @override
  Widget build(BuildContext context) {
    return CustomTooltip(
      richMessage: TextSpan(
        style: TextStyle(
          fontSize: 16,
          color: Colors.white,
          height: 1.6,
        ),
        children: [
          // Status indicators
          TextSpan(
            text: 'Asset Status:\n',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          TextSpan(
            text: '• Red',
            style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red),
          ),
          TextSpan(text: ' - Not downloaded\n'),
          TextSpan(
            text: '• Green',
            style: TextStyle(fontWeight: FontWeight.bold, color: Colors.green),
          ),
          TextSpan(text: ' - Downloaded\n'),
          TextSpan(
            text: '• Blue',
            style:
                TextStyle(fontWeight: FontWeight.bold, color: Colors.lightBlue),
          ),
          TextSpan(text: ' - Last selected URL\n\n'),

          // Actions
          TextSpan(
            text: 'Actions:\n',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          TextSpan(text: '• Click a URL to see options\n'),
          TextSpan(
              text:
                  '• Download button: Attempts to download all missing asset files\n'),
          TextSpan(
              text:
                  '• Backup button: Creates a backup (even with missing asset files)\n'),
          TextSpan(text: '• Cancel button: Cancels downloads'),
        ],
      ),
      child: Icon(
        Icons.info_outline,
        size: 26,
      ),
    );
  }
}
