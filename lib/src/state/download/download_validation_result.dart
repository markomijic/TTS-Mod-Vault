class DomainReachabilityResult {
  final String domain;
  final bool isReachable;

  const DomainReachabilityResult({
    required this.domain,
    required this.isReachable,
  });
}

class DownloadValidationResult {
  final String modName;
  final List<String> unreachableDomains;
  final List<String> invalidUrls;

  const DownloadValidationResult({
    required this.modName,
    this.unreachableDomains = const [],
    this.invalidUrls = const [],
  });

  bool get hasIssues =>
      unreachableDomains.isNotEmpty || invalidUrls.isNotEmpty;
}
