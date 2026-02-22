import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart' show useMemoized;
import 'package:hooks_riverpod/hooks_riverpod.dart'
    show ConsumerWidget, WidgetRef, HookConsumerWidget;
import 'package:tts_mod_vault/src/backups/components/backups_view.dart'
    show BackupsView;
import 'package:tts_mod_vault/src/backups/components/components.dart'
    show BackupSortButton, BackupFilterButton;
import 'package:tts_mod_vault/src/mods/components/components.dart';
import 'package:tts_mod_vault/src/state/provider.dart'
    show backupsSearchQueryProvider, filteredBackupsProvider;

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
              _BackupsTitle(),
              Search(searchQueryProvider: backupsSearchQueryProvider),
              BackupSortButton(),
              BackupFilterButton(),
            ],
          ),
        ),
        Expanded(
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: BackupsView(),
          ),
        ),
        BulkActionsProgressBar(),
      ],
    );
  }
}

class _BackupsTitle extends HookConsumerWidget {
  const _BackupsTitle();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final backupsCount = ref.watch(filteredBackupsProvider).length;

    final tooltipMessage = useMemoized(() {
      return "$backupsCount backups";
    }, [backupsCount]);

    return CustomTooltip(
      message: tooltipMessage,
      waitDuration: const Duration(milliseconds: 300),
      child: SizedBox(
        height: 32,
        child: ToggleButtons(
          // Unselect items colors
          color: Colors.white,
          borderColor: Colors.white,
          // Selected items colors
          selectedColor: Colors.black, // Text
          fillColor: Colors.white, // Background
          selectedBorderColor: Colors.white,
          isSelected: [true],
          borderRadius: BorderRadius.circular(16),
          onPressed: (index) => {},
          children: [
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 10),
              child: Text(
                'Backups',
                style: TextStyle(fontWeight: FontWeight.w500),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
