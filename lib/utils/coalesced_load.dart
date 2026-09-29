import 'package:flutter/widgets.dart';

/// A screen whose data is a request away, read again whenever the backend says
/// something changed.
///
/// Events can arrive faster than a read finishes: a local build republishes
/// every job on each change, and a socket can deliver several at once. A
/// [reload] asked for while a read is running folds into one more read after
/// it, so a burst costs at most two reads, and the last one always sees the
/// latest state.
mixin CoalescedLoad<T extends StatefulWidget> on State<T> {
  bool _reading = false;
  bool _readAgain = false;

  /// One read of everything the screen shows. Called only through [reload].
  @protected
  Future<void> read();

  Future<void> reload() async {
    if (_reading) {
      _readAgain = true;
      return;
    }
    _reading = true;
    try {
      do {
        _readAgain = false;
        await read();
      } while (_readAgain && mounted);
    } finally {
      _reading = false;
    }
  }
}
