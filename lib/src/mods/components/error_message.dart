import 'dart:io' show exit;

import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart'
    show ConsumerWidget, WidgetRef;

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
        ElevatedButton(
          onPressed: () => exit(0),
          child: Text('Exit', style: TextStyle(fontSize: 32)),
        ),
      ],
    );
  }
}
