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
          TextSpan(
            text: 'Red URL',
            style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red),
          ),
          TextSpan(text: ' - asset is not downloaded\n'),
          TextSpan(
            text: 'Green URL',
            style: TextStyle(fontWeight: FontWeight.bold, color: Colors.green),
          ),
          TextSpan(text: ' - asset is downloaded\n'),
          TextSpan(
            text: 'Blue URL',
            style:
                TextStyle(fontWeight: FontWeight.bold, color: Colors.lightBlue),
          ),
          TextSpan(
              text:
                  ' - asset URL has been selected and can be downloaded with the "Download" button\n\n'),
          TextSpan(text: 'Tap on '),
          TextSpan(
            text: 'red URL',
            style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red),
          ),
          TextSpan(text: ' to select it, tap on '),
          TextSpan(
            text: 'blue URL',
            style:
                TextStyle(fontWeight: FontWeight.bold, color: Colors.lightBlue),
          ),
          TextSpan(text: ' to deselect it\nDouble tap on '),
          TextSpan(
            text: 'green URL',
            style: TextStyle(fontWeight: FontWeight.bold, color: Colors.green),
          ),
          TextSpan(
              text:
                  ' to open the file in the file explorer\nPress and hold any URL to copy it to clipboard\nBackup button will create a backup even if some files are missing'),
        ],
      ),
      child: Icon(
        Icons.help_outline,
        size: 24,
      ),
    );
  }
}
