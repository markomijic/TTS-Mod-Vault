enum ExistingBackupStatusEnum {
  upToDate('Up to date'),
  outOfDate('Out of date'),
  noBackup('No backup');

  const ExistingBackupStatusEnum(this.label);

  final String label;
}
