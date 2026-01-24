import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart'
    show ConsumerWidget, WidgetRef;
import 'package:tts_mod_vault/src/backups/components/components.dart'
    show BackupsGrid;
import 'package:tts_mod_vault/src/mods/components/components.dart';
import 'package:tts_mod_vault/src/state/provider.dart'
    show backupsSearchQueryProvider;

class BackupsPage extends ConsumerWidget {
  const BackupsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.only(top: 8),
          child: Row(
            spacing: 8,
            children: [
              Text(
                'Backups',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Search(searchQueryProvider: backupsSearchQueryProvider),
            ],
          ),
        ),
        Expanded(
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: BackupsGrid(),
          ),
        ),
        BulkActionsProgressBar(),
      ],
    );
  }
}
