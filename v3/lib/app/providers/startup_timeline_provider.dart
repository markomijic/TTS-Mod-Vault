import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:tts_mod_vault/bootstrap/startup_timeline.dart';

/// The process start-up timeline. `main.dart` overrides it with the instance
/// created at `main()` entry; without an override (tests) a fresh timeline
/// starts when first read, so `sinceMainMs` values are simply small.
final startupTimelineProvider = Provider<StartupTimeline>(
  (ref) => StartupTimeline(),
);
