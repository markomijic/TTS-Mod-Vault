import 'package:flutter/material.dart';
import 'package:tts_mod_vault/src/backups/components/backups_grid_card.dart'
    show BackupsGridCard;
import 'package:tts_mod_vault/src/state/backup/models/existing_backup_model.dart'
    show ExistingBackup;

class BackupsGrid extends StatelessWidget {
  final List<ExistingBackup> backups;

  const BackupsGrid({super.key, required this.backups});

  @override
  Widget build(BuildContext context) {
    if (backups.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.only(right: 40),
          child: Text(
            'No backups found',
            style: TextStyle(fontSize: 48),
          ),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final crossAxisCount =
            constraints.maxWidth > 500 ? constraints.maxWidth ~/ 220 : 1;

        return GridView.builder(
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            mainAxisSpacing: 20,
            crossAxisSpacing: 20,
            crossAxisCount: crossAxisCount,
          ),
          itemCount: backups.length,
          itemBuilder: (context, index) {
            return BackupsGridCard(
              backup: backups[index],
            );
          },
        );
      },
    );
  }
}
