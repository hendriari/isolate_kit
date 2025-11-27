import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:isolate_kit/isolate_kit.dart';

/// True cancellation token with listener support
class CancellationToken {
  bool _isCancelled = false;
  final List<VoidCallback> _listeners = [];
  final Completer<void> _cancelledCompleter = Completer<void>();

  bool get isCancelled => _isCancelled;

  Future<void> get cancelled => _cancelledCompleter.future;

  void cancel() {
    if (_isCancelled) return;
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
  }

  void throwIfCancelled() {
    if (_isCancelled) throw TaskCancelledException();
  }

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

  void removeListener(VoidCallback listener) => _listeners.remove(listener);

  /// Combine multiple tokens - cancelled if ANY token is cancelled
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

class CombinedCancellationToken extends CancellationToken {
  final List<CancellationToken> _sourceTokens = [];
  final List<VoidCallback> _callbacks = [];

  void dispose() {
    for (int i = 0; i < _sourceTokens.length; i++) {
      _sourceTokens[i].removeListener(_callbacks[i]);
    }
    _sourceTokens.clear();
    _callbacks.clear();
  }
}