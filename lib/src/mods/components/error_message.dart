import 'dart:io' show exit;

import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart'
    show ConsumerWidget, WidgetRef;
import 'package:tts_mod_vault/src/utils.dart'
    show openUrl, showSnackBar, steamDiscussionUrl;

class ErrorMessage extends ConsumerWidget {
  final Object e;

  const ErrorMessage({super.key, required this.e});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      spacing: 20,
      children: [
        Text(
          'Something went wrong, please try restarting the application\nError: '
          '$e',
          style: TextStyle(
            fontSize: 32,
            fontWeight: FontWeight.bold,
          ),
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          spacing: 16,
          children: [
            ElevatedButton(
              onPressed: () async {
                final result = await openUrl(steamDiscussionUrl);
                if (!result && context.mounted) {
                  showSnackBar(context, "Failed to open: $steamDiscussionUrl");
                }
              },
              child: Text('Help & Feedback', style: TextStyle(fontSize: 24)),
            ),
            ElevatedButton(
              onPressed: () => exit(0),
              child: Text('Exit', style: TextStyle(fontSize: 24)),
            ),
          ],
        ),
      ],
    );
  }
}
