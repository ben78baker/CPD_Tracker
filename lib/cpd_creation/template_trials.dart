import 'dart:math' as math;

const templateTrialDuration = Duration(days: 7);

enum TemplateTrialState { eligible, active, ended, unavailable, owned }

class TemplateTrialStatus {
  const TemplateTrialStatus(this.state, {this.started, this.remaining});

  final TemplateTrialState state;
  final DateTime? started;
  final Duration? remaining;
  DateTime? get expires => started?.add(templateTrialDuration);
  bool get active => state == TemplateTrialState.active;
}

/// Local time is useful for the internal rehearsal. Production enforcement
/// needs a verified time and a store-backed or equivalent redemption proof.
class TrialClock {
  TrialClock({DateTime Function()? utcNow, Duration Function()? elapsed})
    : _utcNow = utcNow ?? DateTime.now,
      _elapsed = elapsed ?? _monotonicClock() {
    _wallAtStart = _utcNow().toUtc();
    _elapsedAtStart = _elapsed();
  }

  final DateTime Function() _utcNow;
  final Duration Function() _elapsed;
  late final DateTime _wallAtStart;
  late final Duration _elapsedAtStart;

  static Duration Function() _monotonicClock() {
    final stopwatch = Stopwatch()..start();
    return () => stopwatch.elapsed;
  }

  DateTime get wall => _utcNow().toUtc();
  DateTime get monotonicEstimate =>
      _wallAtStart.add(_elapsed() - _elapsedAtStart);
}

/// The ledger is scoped to the trial authority, outside all recording stores,
/// archives and migration snapshots. A missing ledger is an authority error.
abstract interface class TemplateTrialLedger {
  Future<TemplateTrialStatus> check(
    String templateId, {
    required TrialClock clock,
    required bool start,
  });
}

/// The storage adapter evaluates and persists this result in one transaction.
({TemplateTrialStatus status, int observed, int? activated}) evaluateTrial({
  required TrialClock clock,
  required int previousObservation,
  required int? activation,
  required bool start,
}) {
  final wall = clock.wall.millisecondsSinceEpoch;
  final effective = math.max(
    wall,
    clock.monotonicEstimate.millisecondsSinceEpoch,
  );
  final interval = templateTrialDuration.inMilliseconds;
  DateTime utc(int instant) =>
      DateTime.fromMillisecondsSinceEpoch(instant, isUtc: true);
  if (previousObservation < 0 ||
      (activation != null &&
          (activation < 0 || activation > previousObservation))) {
    throw const FormatException('Invalid trial history.');
  }
  final observed = math.max(previousObservation, effective);
  if (activation != null && observed >= activation + interval) {
    return (
      status: TemplateTrialStatus(
        TemplateTrialState.ended,
        started: utc(activation),
      ),
      observed: observed,
      activated: activation,
    );
  }
  // Reject a backwards wall clock across restarts. A running session can use
  // its own monotonic lower bound to stay usable and age normally offline.
  if (effective < previousObservation) {
    return (
      status: const TemplateTrialStatus(TemplateTrialState.unavailable),
      observed: previousObservation,
      activated: activation,
    );
  }
  final activated = activation ?? (start ? observed : null);
  return (
    status: activated == null
        ? const TemplateTrialStatus(TemplateTrialState.eligible)
        : TemplateTrialStatus(
            TemplateTrialState.active,
            started: utc(activated),
            remaining: Duration(milliseconds: activated + interval - observed),
          ),
    observed: observed,
    activated: activated,
  );
}
