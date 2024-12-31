import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:tts_mod_vault/src/components/toolbar.dart';

class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SafeArea(
      child: Scaffold(
        body: Column(
          children: [
            SizedBox(
              height: 50,
              child: Align(
                alignment: Alignment.bottomLeft,
                child: Toolbar(),
              ),
            ),
            Expanded(
              child: Text('Settings page'),
            ),
          ],
        ),
      ),
    );
  }
}
