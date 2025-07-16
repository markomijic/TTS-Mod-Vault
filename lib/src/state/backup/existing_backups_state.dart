import 'package:tts_mod_vault/src/state/backup/models/existing_backup_model.dart'
    show ExistingBackup;

class ExistingBackupsState {
  final List<ExistingBackup> backups;

  const ExistingBackupsState({
    required this.backups,
  });

  factory ExistingBackupsState.empty() => const ExistingBackupsState(
        backups: [],
      );

  ExistingBackupsState copyWith({
    List<ExistingBackup>? backups,
  }) {
    return ExistingBackupsState(
      backups: backups ?? this.backups,
    );
  }
}
