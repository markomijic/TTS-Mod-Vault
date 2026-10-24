/// The Settings "Check all Mods and Saves domains" action: whether every host
/// referenced by the asset URLs of Mods and Saves answers. Port of 2.x
/// `checkAllModAndSaveDomains` (commit `051741c`).
library;

import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:tts_mod_vault/app/providers/infrastructure_providers.dart';
import 'package:tts_mod_vault/core/logging/app_log.dart';
import 'package:tts_mod_vault/data/net/domain_reachability_checker.dart';
import 'package:tts_mod_vault/domain/enums/mod_type.dart';
import 'package:tts_mod_vault/features/downloads/application/downloads_providers.dart'
    show checkDomainsProgressLabel;
import 'package:tts_mod_vault/features/downloads/application/network_options.dart';
import 'package:tts_mod_vault/features/operations/application/operation_runner.dart';

/// The mod types whose domains are checked; saved objects are left out, as
/// in 2.x.
const Set<ModType> checkedDomainModTypes = {ModType.mod, ModType.save};

/// Starts the domain check on the runner.
final domainCheckServiceProvider = Provider<DomainCheckService>(
  DomainCheckService.new,
);

/// Starts [CheckDomainsOperation]s. Not `final`, so widget tests can
/// substitute a fake.
class DomainCheckService {
  /// Creates the service on [ref].
  DomainCheckService(this.ref);

  /// Supplies the runner and the operation's collaborators.
  final Ref ref;

  /// Checks every domain of Mods and Saves. Throws [StateError] when another
  /// operation is running; cancellation comes back as
  /// [DomainCheckResult.cancelled].
  Future<DomainCheckResult> checkAllModAndSaveDomains() => ref
      .read(operationRunnerProvider.notifier)
      .run(CheckDomainsOperation(ref: ref));
}

/// Checks each unique host among the cached asset URLs of Mods and Saves,
/// excluded domains included, with `concurrentDownloads` workers and the
/// checker's cache bypassed. Logs one warning per unreachable host and a
/// summary; nothing is persisted.
final class CheckDomainsOperation extends Operation<DomainCheckResult> {
  /// Creates the operation.
  CheckDomainsOperation({required this.ref});

  /// Supplies the database, the checker and the network options.
  final Ref ref;

  @override
  OperationKind get kind => OperationKind.checkDomains;

  @override
  DomainCheckResult? cancelledResult() =>
      const DomainCheckResult(domains: [], cancelled: true);

  @override
  Future<DomainCheckResult> run(OperationContext ctx) async {
    final log = ctx.log;
    final options = await ref
        .read(networkOptionsProvider.notifier)
        .ensureLoaded();
    final urls = await ref
        .read(appDatabaseProvider)
        .libraryQueries
        .distinctAssetUrls(checkedDomainModTypes);
    ctx.checkCancelled();

    log.info(
      LogSource.urlCheck,
      'Checking the domains of ${urls.length} URL(s) of Mods and Saves',
      operationId: ctx.operationId,
    );
    ctx.report(OperationProgress(kind: kind, label: checkDomainsProgressLabel));

    final result = await ref
        .read(domainReachabilityCheckerProvider)
        .checkUrls(
          urls,
          concurrency: options.concurrentDownloads,
          forceRefresh: true,
          token: ctx.token,
          onProgress: (done, total) => ctx.report(
            OperationProgress(
              kind: kind,
              label: checkDomainsProgressLabel,
              done: done,
              total: total,
            ),
          ),
        );

    if (result.cancelled) {
      log.warning(
        LogSource.urlCheck,
        'Domain check cancelled after ${result.domains.length} domain(s)',
        operationId: ctx.operationId,
      );
      return result;
    }

    final unreachable = result.unreachable;
    for (final host in unreachable) {
      log.warning(
        LogSource.urlCheck,
        'Domain is not reachable: $host',
        operationId: ctx.operationId,
      );
    }
    final total = result.domains.length;
    final message =
        'Checked $total domain(s) of Mods and Saves: '
        '${unreachable.isEmpty ? 'all reachable' : '${unreachable.length} not reachable'}';
    if (unreachable.isEmpty) {
      log.success(LogSource.urlCheck, message, operationId: ctx.operationId);
    } else {
      log.warning(
        LogSource.urlCheck,
        message,
        details: unreachable.join('\n'),
        operationId: ctx.operationId,
      );
    }
    return result;
  }
}
