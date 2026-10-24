// The Settings domain check: the results dialog (summary, unreachable
// first, empty state) and the Network section button that launches it.

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tts_mod_vault/data/net/domain_reachability_checker.dart';
import 'package:tts_mod_vault/features/settings/application/check_domains_operation.dart';
import 'package:tts_mod_vault/features/settings/presentation/domain_reachability_dialog.dart';
import 'package:tts_mod_vault/features/settings/presentation/network_section.dart';

import '../../images_viewer/themed_app.dart';

const List<DomainReachability> _domains = [
  (domain: 'a.example', reachable: true),
  (domain: 'z.example', reachable: false),
  (domain: 'm.example', reachable: true),
  (domain: 'b.example', reachable: false),
];

/// Answers the domain check with whatever [next] completes with.
final class _FakeDomainCheckService extends DomainCheckService {
  _FakeDomainCheckService(super.ref);

  Completer<DomainCheckResult> next = Completer<DomainCheckResult>();
  int calls = 0;

  @override
  Future<DomainCheckResult> checkAllModAndSaveDomains() {
    calls++;
    return next.future;
  }
}

void main() {
  Future<void> pumpDialog(
    WidgetTester tester,
    List<DomainReachability> domains,
  ) => pumpThemedApp(
    tester,
    home: Scaffold(body: DomainReachabilityDialog(domains: domains)),
  );

  testWidgets('summarises and lists unreachable domains first', (tester) async {
    await pumpDialog(tester, _domains);

    expect(find.text('Domain reachability results'), findsOneWidget);
    expect(find.text('2 reachable, 2 unreachable (4 total)'), findsOneWidget);

    final order = [
      for (final tile in tester.widgetList<ListTile>(find.byType(ListTile)))
        (tile.key! as ValueKey<String>).value,
    ];
    expect(order, [
      'domain-result-b.example',
      'domain-result-z.example',
      'domain-result-a.example',
      'domain-result-m.example',
    ]);
    expect(find.text('Unreachable'), findsNWidgets(2));
    expect(find.text('Reachable'), findsNWidgets(2));
    expect(find.byIcon(Icons.cancel), findsNWidgets(2));
    expect(find.byIcon(Icons.check_circle), findsNWidgets(2));
    expect(find.widgetWithText(SelectableText, 'z.example'), findsOneWidget);
  });

  testWidgets('says so when no domain was found', (tester) async {
    await pumpDialog(tester, const []);

    expect(find.text('No domains were found in Mods or Saves'), findsOneWidget);
    expect(find.byType(ListTile), findsNothing);
  });

  group('CheckDomainsButton', () {
    late _FakeDomainCheckService service;

    Future<void> pumpButton(WidgetTester tester) => pumpThemedApp(
      tester,
      overrides: [
        domainCheckServiceProvider.overrideWith(
          (ref) => service = _FakeDomainCheckService(ref),
        ),
      ],
      home: const Scaffold(body: Center(child: CheckDomainsButton())),
    );

    testWidgets('shows a spinner while running, then the results', (
      tester,
    ) async {
      await pumpButton(tester);
      expect(find.text('Check all Mods and Saves domains'), findsOneWidget);

      await tester.tap(find.text('Check all Mods and Saves domains'));
      await tester.pump();
      expect(service.calls, 1);
      expect(find.text('Checking domains...'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);

      service.next.complete(
        const DomainCheckResult(domains: _domains, cancelled: false),
      );
      await tester.pumpAndSettle();
      expect(find.byType(DomainReachabilityDialog), findsOneWidget);
      expect(find.text('Check all Mods and Saves domains'), findsOneWidget);

      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      expect(find.byType(DomainReachabilityDialog), findsNothing);
    });

    testWidgets('a cancelled run shows nothing', (tester) async {
      await pumpButton(tester);
      await tester.tap(find.text('Check all Mods and Saves domains'));
      await tester.pump();
      service.next.complete(
        const DomainCheckResult(domains: [], cancelled: true),
      );
      await tester.pumpAndSettle();
      expect(find.byType(DomainReachabilityDialog), findsNothing);
      expect(find.text('Check all Mods and Saves domains'), findsOneWidget);
    });
  });
}
