import 'package:flutter/material.dart';
import 'package:tts_mod_vault/src/state/download/download_validation_result.dart'
    show DownloadValidationResult, DomainReachabilityResult;

Future<void> showDownloadValidationResultsDialog(
  BuildContext context,
  Iterable<DownloadValidationResult> results,
) async {
  final issueResults = results.where((result) => result.hasIssues).toList();
  if (issueResults.isEmpty || !context.mounted) return;

  await showDialog<void>(
    context: context,
    builder: (_) => _DownloadValidationResultsDialog(results: issueResults),
  );
}

Future<void> showDomainReachabilityResultsDialog(
  BuildContext context,
  List<DomainReachabilityResult> results,
) async {
  if (!context.mounted) return;

  await showDialog<void>(
    context: context,
    builder: (_) => _DomainReachabilityResultsDialog(results: results),
  );
}

class _DownloadValidationResultsDialog extends StatelessWidget {
  final List<DownloadValidationResult> results;

  const _DownloadValidationResultsDialog({required this.results});

  @override
  Widget build(BuildContext context) {
    final unreachable = results
        .where((result) => result.unreachableDomains.isNotEmpty)
        .toList();
    final invalid =
        results.where((result) => result.invalidUrls.isNotEmpty).toList();

    return AlertDialog(
      title: const Text('Download check results'),
      content: SizedBox(
        width: 650,
        height: 420,
        child: ListView(
          children: [
            if (unreachable.isNotEmpty) ...[
              const _ResultHeading(
                icon: Icons.cloud_off,
                color: Colors.orange,
                title: 'Domains unreachable',
                description:
                    'These domains could not be reached from the current network. Their resources were not marked invalid.',
              ),
              ...unreachable.map(
                (result) => _GroupedResult(
                  title: result.modName,
                  values: result.unreachableDomains,
                ),
              ),
            ],
            if (unreachable.isNotEmpty && invalid.isNotEmpty)
              const Divider(height: 32),
            if (invalid.isNotEmpty) ...[
              const _ResultHeading(
                icon: Icons.link_off,
                color: Colors.redAccent,
                title: 'Invalid resources',
                description:
                    'The domains are reachable, but these resource URLs are invalid.',
              ),
              ...invalid.map(
                (result) => _GroupedResult(
                  title: result.modName,
                  values: result.invalidUrls,
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        ElevatedButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    );
  }
}

class _DomainReachabilityResultsDialog extends StatelessWidget {
  final List<DomainReachabilityResult> results;

  const _DomainReachabilityResultsDialog({required this.results});

  @override
  Widget build(BuildContext context) {
    final reachableCount = results.where((result) => result.isReachable).length;
    final sorted = [...results]
      ..sort((a, b) {
        if (a.isReachable != b.isReachable) {
          return a.isReachable ? 1 : -1;
        }
        return a.domain.compareTo(b.domain);
      });

    return AlertDialog(
      title: const Text('Domain reachability results'),
      content: SizedBox(
        width: 560,
        height: 420,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              results.isEmpty
                  ? 'No domains were found in Mods or Saves.'
                  : '$reachableCount reachable, ${results.length - reachableCount} unreachable (${results.length} total)',
            ),
            const SizedBox(height: 12),
            if (sorted.isNotEmpty)
              Expanded(
                child: ListView.builder(
                  itemCount: sorted.length,
                  itemBuilder: (context, index) {
                    final result = sorted[index];
                    return ListTile(
                      dense: true,
                      leading: Icon(
                        result.isReachable ? Icons.check_circle : Icons.cancel,
                        color: result.isReachable
                            ? Colors.green
                            : Colors.redAccent,
                      ),
                      title: SelectableText(result.domain),
                      trailing:
                          Text(result.isReachable ? 'Reachable' : 'Unreachable'),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
      actions: [
        ElevatedButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    );
  }
}

class _ResultHeading extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String description;

  const _ResultHeading({
    required this.icon,
    required this.color,
    required this.title,
    required this.description,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(description),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _GroupedResult extends StatelessWidget {
  final String title;
  final List<String> values;

  const _GroupedResult({required this.title, required this.values});

  @override
  Widget build(BuildContext context) {
    return ExpansionTile(
      initiallyExpanded: true,
      title: Text('$title (${values.length})'),
      children: values
          .map(
            (value) => ListTile(
              dense: true,
              title: SelectableText(value),
            ),
          )
          .toList(),
    );
  }
}
