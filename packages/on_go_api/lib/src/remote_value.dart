import 'dart:async';

import 'event_socket.dart';

/// A server value that can be read now and watched — what every HTTP `watch*`
/// is built from.
///
/// While something listens it fetches once, then keeps the value current:
/// applies (or re-fetches on) a named event, re-fetches whenever the event
/// socket reconnects (events during a gap are not queued), and polls when
/// there is no event to rely on. Listeners share one fetch, so a screen
/// rebuilding its `StreamBuilder` does not become a request per build.
class RemoteValue<T> {
  RemoteValue({
    required Future<T> Function() fetch,
    EventSocket? events,
    String? eventName,
    T? Function(ApiEvent event)? fromEvent,
    bool Function(ApiEvent event)? matches,
    Duration? pollInterval,
    this.minRefetchGap = const Duration(seconds: 2),
    DateTime Function()? clock,
  })  : _fetch = fetch,
        _events = events,
        _eventName = eventName,
        _fromEvent = fromEvent,
        _matches = matches,
        _pollInterval = pollInterval,
        _clock = clock ?? DateTime.now;

  final Future<T> Function() _fetch;
  final EventSocket? _events;
  final String? _eventName;
  final T? Function(ApiEvent event)? _fromEvent;
  final bool Function(ApiEvent event)? _matches;
  final Duration? _pollInterval;
  final DateTime Function() _clock;

  /// A reconnect or a new listener within this long of the last fetch reuses
  /// it rather than asking again.
  final Duration minRefetchGap;

  final StreamController<T> _updates = StreamController<T>.broadcast();

  T? _value;
  bool _hasValue = false;
  int _listeners = 0;
  Future<T>? _inFlight;
  DateTime? _lastFetch;
  StreamSubscription<ApiEvent>? _eventWatch;
  StreamSubscription<void>? _reconnectWatch;
  Timer? _poll;

  bool get hasValue => _hasValue;

  T? get value => _value;

  /// The last value (when there is one), then every change. Fetch failures
  /// arrive as stream errors; the last good value stays.
  Stream<T> watch() => Stream<T>.multi((listener) {
        if (_hasValue) listener.add(_value as T);
        final subscription = _updates.stream.listen(listener.add, onError: listener.addError);
        if (_listeners++ == 0) _activate();
        listener.onCancel = () {
          unawaited(subscription.cancel());
          if (--_listeners == 0) _deactivate();
        };
      });

  /// Fetches now, sharing a fetch already under way.
  Future<T> refresh() {
    final pending = _inFlight;
    if (pending != null) return pending;

    final future = _fetch().then(
      (value) {
        _lastFetch = _clock();
        set(value);
        return value;
      },
      onError: (Object error, StackTrace stack) {
        if (!_updates.isClosed) _updates.addError(error, stack);
        return Future<T>.error(error, stack);
      },
    );
    _inFlight = future;
    future.then<void>((_) {}, onError: (Object _) {}).whenComplete(() {
      if (identical(_inFlight, future)) _inFlight = null;
    });
    return future;
  }

  /// [refresh], for callers with nothing to do about a failure.
  void refreshQuietly({bool force = false}) {
    final last = _lastFetch;
    if (!force && last != null && _clock().difference(last) < minRefetchGap) return;
    refresh().then<void>((_) {}, onError: (Object _) {});
  }

  /// Publishes a value the caller already has — the response to a write.
  void set(T value) {
    _value = value;
    _hasValue = true;
    if (!_updates.isClosed) _updates.add(value);
  }

  void _activate() {
    refreshQuietly();
    final events = _events;
    if (events != null) {
      final name = _eventName;
      if (name != null) _eventWatch = events.on(name).listen(_onEvent);
      _reconnectWatch = events.connected.listen((_) => refreshQuietly());
    }
    final interval = _pollInterval;
    if (interval != null) _poll = Timer.periodic(interval, (_) => refreshQuietly());
  }

  void _onEvent(ApiEvent event) {
    final matches = _matches;
    if (matches != null && !matches(event)) return;
    final fromEvent = _fromEvent;
    if (fromEvent != null) {
      try {
        final value = fromEvent(event);
        if (value != null) {
          set(value);
          return;
        }
      } catch (_) {
        // Data this app could not read; ask the server instead.
      }
    }
    refreshQuietly(force: true);
  }

  void _deactivate() {
    unawaited(_eventWatch?.cancel());
    unawaited(_reconnectWatch?.cancel());
    _eventWatch = null;
    _reconnectWatch = null;
    _poll?.cancel();
    _poll = null;
  }

  Future<void> dispose() async {
    _deactivate();
    await _updates.close();
  }
}
