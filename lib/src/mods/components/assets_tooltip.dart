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
            text: 'Asset file status:\n',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          TextSpan(
            text: '• Red',
            style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red),
          ),
          TextSpan(text: ' - Missing\n'),
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
          TextSpan(
            text: '''
• Left/right-click a URL to see options 
• Download button: Attempt to download all missing asset files
• Backup button: Create a backup out of downloaded asset files
• Update URLs: Replaces old prefixes of URLs with new one
• Menu button: additional options - deleting asset files, copying missing URLs''',
            style: TextStyle(height: 2),
          ),
        ],
      ),
      child: Icon(
        Icons.info_outline,
        size: 32,
      ),
    );
  }
}
