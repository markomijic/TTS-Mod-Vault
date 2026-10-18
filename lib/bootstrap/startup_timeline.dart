/// Wall-clock milestones of one process start, measured from `main()`.
///
/// `main()` creates the instance first thing; `bootstrap()` records its
/// steps on it and the startup code logs `sinceMainMs=` offsets taken from
/// [elapsedMs], so the log shows where the time between process start and
/// "Library refresh finished" goes. Pure bookkeeping, no IO.
final class StartupTimeline {
  /// Starts the clock now.
  StartupTimeline() : _stopwatch = Stopwatch()..start();

  final Stopwatch _stopwatch;
  final Map<String, int> _marks = {};

  /// Milliseconds since the timeline was created.
  int get elapsedMs => _stopwatch.elapsedMilliseconds;

  /// Records [name] at the current [elapsedMs] (first call wins) and returns
  /// that offset.
  int mark(String name) => _marks.putIfAbsent(name, () => elapsedMs);

  /// Offset of a recorded mark, or null.
  int? operator [](String name) => _marks[name];

  /// Whether [name] was marked.
  bool has(String name) => _marks.containsKey(name);

  /// Mark set by `main()` once the first frame has been rendered.
  static const String firstFrame = 'firstFrame';

  /// Mark set by the startup controller when the first library refresh is
  /// requested.
  static const String refreshRequested = 'refreshRequested';
}
