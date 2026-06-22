class ModUrlCheckResult {
  final String modName;
  final List<String> invalidUrls; // empty == all valid
  final bool cancelled; // check did not finish for this mod

  const ModUrlCheckResult({
    required this.modName,
    required this.invalidUrls,
    this.cancelled = false,
  });
}
