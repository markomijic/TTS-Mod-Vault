import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

void showChangelogDialog(BuildContext context) {
  showDialog(
    context: context,
    builder: (BuildContext context) {
      return BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 2, sigmaY: 2),
        child: AlertDialog(
          title: Text('Changelog'),
          content: SizedBox(
            width: 1100,
            height: 550,
            child: SingleChildScrollView(
              child: Text(
                getChangelog(),
                style: TextStyle(fontSize: 18),
              ),
            ),
          ),
          actions: [
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: Text('Close'),
            )
          ],
        ),
      );
    },
  );
}

String getChangelog() {
  return """
v1.1.0
Features:
· Search
· Viewing images
· Support for Saves and Saved Objects
· Separate selection of Mods and Saves folders
· Opening audio, image and pdf files
· URL replacement tool

Changes:
· Reworked loading system for faster load times
· New caching system for better performance
· General improvements and fixes


v1.0.2
Changes:
· Fixed mods not appearing if they were in a folder within the Workshop folder
· Fixed issue where downloading files from Dropbox links, where files were deleted, incorrectly marked them as downloaded


v1.0.1
Changes:
· Fixed asset lists not updating due to incorrect reading of last time mod was updated
· Added Download from GitHub button to "Check for updates" dialog
· Performance improvements when opening file explorer


v1.0.0
Features:
· Download - Download all mod assets locally
· Backup - Create backups of your mods
· Import Backup - Restore existing ttsmod files backups
· Cleanup - Remove unused cached files that aren't part of your installed mods
""";
}
