import 'dart:async';

/// Coordinates the legacy writers in the application's main Dart isolate.
final class LegacyWriteGate {
  static final instance = LegacyWriteGate();

  final _scopeKey = Object();
  var _writers = 0;
  var _frozen = false;
  var _retired = false;
  Completer<void>? _drained;

  Future<T> write<T>(Future<T> Function() action) async {
    final scope = Zone.current[_scopeKey] as _WriteScope?;
    if (scope?.active == true) return action();
    if (_frozen || _retired) {
      throw StateError('Legacy storage is unavailable for writes.');
    }
    final writer = _WriteScope();
    _writers++;
    try {
      return await runZoned(action, zoneValues: {_scopeKey: writer});
    } finally {
      writer.active = false;
      if (--_writers == 0) _drained?.complete();
    }
  }

  /// Reject new work immediately, then let admitted composite writes finish.
  Future<T> freeze<T>(Future<T> Function() action) async {
    if (_frozen || _retired || Zone.current[_scopeKey] is _WriteScope) {
      throw StateError('Legacy storage cannot be frozen in this context.');
    }
    _frozen = true;
    try {
      if (_writers != 0) {
        _drained = Completer<void>();
        await _drained!.future;
      }
      return await action();
    } finally {
      _drained = null;
      _frozen = false;
    }
  }

  /// Called only after the durable production authority marker commits.
  void seal() {
    if (!_frozen || _writers != 0) {
      throw StateError('Only a quiescent legacy store can be sealed.');
    }
    _retired = true;
  }
}

class _WriteScope {
  bool active = true;
}
