enum BackupStatusEnum {
  upToDate('Up to date'),
  outOfDate('Out of date'),
  noBackup('No backup');

  const BackupStatusEnum(this.label);

  final String label;
}
