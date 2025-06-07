import 'package:flutter/material.dart';

class AssetsTooltip extends StatelessWidget {
  const AssetsTooltip({super.key});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        border: Border.all(color: Colors.white, width: 2),
        borderRadius: BorderRadius.circular(8),
      ),
      richMessage: TextSpan(
        style: TextStyle(
          fontSize: 16,
          color: Colors.white,
          height: 1.5,
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
          TextSpan(text: ' - Selected (right-clicked)\n\n'),

          // Actions
          TextSpan(
            text: 'Actions:\n',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          TextSpan(text: '• Right-click any URL for asset options\n'),
          TextSpan(
              text:
                  '• Click on Steam icon to open Workshop page of selected mod\n'),
          TextSpan(
              text:
                  '• Download button: Try to download all missing asset files\n'),
          TextSpan(text: '• Cancel button: Cancel all downloads\n'),
          TextSpan(
              text:
                  '• Backup button: Create backup (even with missing asset files)'),
        ],
      ),
      child: Icon(
        Icons.help_outline,
        size: 26,
      ),
    );
  }
}
