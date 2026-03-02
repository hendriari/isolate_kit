import 'dart:async';

import 'package:flutter/material.dart';
import 'package:isolate_kit/isolate_kit.dart';

/// A token that can be used to signal cancellation of a task.
///
/// It provides mechanisms for listeners to be notified when cancellation occurs
/// and for code to check the cancellation status.
class CancellationToken {
  bool _isCancelled = false;
  final List<VoidCallback> _listeners = [];
  final Completer<void> _cancelledCompleter = Completer<void>();

  /// Returns true if the token has been cancelled.
  bool get isCancelled => _isCancelled;

  /// A future that completes when the token is cancelled.
  Future<void> get cancelled => _cancelledCompleter.future;

  /// Signals cancellation. All listeners will be notified.
  /// Returns true if the token was successfully cancelled, or false if it was already cancelled.
  Future<bool> cancel() async {
    if (_isCancelled) return false;
    _isCancelled = true;

    if (!_cancelledCompleter.isCompleted) {
      _cancelledCompleter.complete();
    }

    for (final listener in List.of(_listeners)) {
      try {
        listener();
      } catch (e) {
        debugPrint('CancellationToken listener error: $e');
      }
    }
    _listeners.clear();
    return true;
  }

  /// Throws a [TaskCancelledException] if the token has been cancelled.
  void throwIfCancelled() {
    if (_isCancelled) throw TaskCancelledException();
  }

  /// Adds a listener to be called when the token is cancelled.
  /// If the token is already cancelled, the listener is called immediately.
  void addListener(VoidCallback listener) {
    if (_isCancelled) {
      try {
        listener();
      } catch (e) {
        debugPrint('CancellationToken listener error on immediate call: $e');
      }
      return;
    }
    _listeners.add(listener);
  }

  /// Removes a previously added listener.
  void removeListener(VoidCallback listener) => _listeners.remove(listener);

  /// Combines multiple tokens into one. The returned token will be cancelled
  /// if any of the source tokens are cancelled.
  static CombinedCancellationToken combine(List<CancellationToken> tokens) {
    final combined = CombinedCancellationToken();

    for (final token in tokens) {
      void cb() => combined.cancel();
      token.addListener(cb);
      combined._sourceTokens.add(token);
      combined._callbacks.add(cb);
    }

    return combined;
  }
}

/// A token that aggregates multiple [CancellationToken]s.
class CombinedCancellationToken extends CancellationToken {
  final List<CancellationToken> _sourceTokens = [];
  final List<VoidCallback> _callbacks = [];

  /// Disconnects from all source tokens.
  void dispose() {
    for (int i = 0; i < _sourceTokens.length; i++) {
      _sourceTokens[i].removeListener(_callbacks[i]);
    }
    _sourceTokens.clear();
    _callbacks.clear();
  }
}
