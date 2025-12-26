import 'package:tts_mod_vault/src/state/backup/models/existing_backup_model.dart'
    show ExistingBackup;

class ExistingBackupsState {
  final List<ExistingBackup> backups;
  final bool deletingBackup;

  const ExistingBackupsState({
    required this.backups,
    this.deletingBackup = false,
  });

  factory ExistingBackupsState.empty() => const ExistingBackupsState(
        backups: [],
      );

  ExistingBackupsState copyWith({
    List<ExistingBackup>? backups,
    bool? deletingBackup,
  }) {
    return ExistingBackupsState(
      backups: backups ?? this.backups,
      deletingBackup: deletingBackup ?? this.deletingBackup,
    );
  }
}
