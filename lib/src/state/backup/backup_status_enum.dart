enum ExistingBackupStatusEnum {
  upToDate('Up to date'),
  outOfDate('Out of date'),
  assetCountMismatch('Asset count mismatch'),
  noBackup('No backup');

  const ExistingBackupStatusEnum(this.label);

  final String label;
}
