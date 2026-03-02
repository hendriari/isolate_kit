# Isolate Kit 🚀

A powerful and production-ready Flutter package for managing background tasks using Dart Isolates. It provides a robust architecture for running heavy computations with full support for cancellation, real-time progress tracking, task prioritization, and intelligent isolate pooling.

[![pub version](https://img.shields.io/pub/v/isolate_kit.svg)](https://pub.dev/packages/isolate_kit)

## ✨ Key Features

- **🔄 Efficient Backgrounding**: Move heavy logic (JSON parsing, image processing, crypto) off the UI thread effortlessly.
- **⚡ Intelligent Pooling**: Scale your app with an Isolate Pool that automatically balances load across multiple workers.
- **🎯 Smart Prioritization**: Use `TaskPriority` to ensure critical UI-blocking tasks run before background syncs.
- **📊 Real-time Progress**: Built-in `sendProgress` callback to update your UI with percentages and custom messages.
- **🚫 True Cancellation**: Stop tasks mid-execution using `CancellationToken` to save CPU and battery.
- **⏱️ Robust Timeout**: Prevent "zombie" tasks with automatic timeout handling and isolate recovery.
- **🔥 Warmup Support**: Eliminate first-run latency by pre-warming isolates or pools.
- **♻️ Auto Resource Management**: Automatically dispose isolates when idle.
- **📱 Lifecycle Aware**: Responsive to application lifecycle changes (disposes on detach, pauses on idle).
- **🎨 Type-Safe & Generic**: Fully typed API for both commands and results.

## 📦 Installation

Add to your `pubspec.yaml`:

```yaml
dependencies:
  isolate_kit: ^1.0.1
```

## 🚀 Quick Start

### 1. Define Your Task

Extend `IsolateTask<TCommand, TResult>` to encapsulate your logic.

```dart
class MyComputeTask extends IsolateTask<int, int> {
  final int iterations;
  MyComputeTask(this.iterations);

  @override
  int get command => iterations;

  @override
  Map<String, dynamic> get payload => {'count': iterations};

  @override
  Future<int> execute({
    void Function(TaskProgress)? sendProgress,
    CancellationToken? cancellationToken,
  }) async {
    int sum = 0;
    for (int i = 0; i < iterations; i++) {
      // 1. Always check for cancellation in loops
      cancellationToken?.throwIfCancelled();

      sum += i;

      // 2. Report progress
      if (i % 100 == 0) {
        sendProgress?.call(TaskProgress(
          percentage: i / iterations,
          message: 'Calculating $i/$iterations...',
        ));
      }
    }
    return sum;
  }
}
```

### 2. Setup & Registration

Register your tasks in the `IsolateTaskRegistry` so the worker isolate knows how to recreate them.

```dart
final registry = IsolateTaskRegistry()
  ..register<MyComputeTask>(
    'MyComputeTask',
    (payload, _) => MyComputeTask(payload['count']),
  );

final isolateKit = IsolateKit.instance(
  name: 'main_worker',
  taskRegistry: registry,
  usePool: true,
  poolSize: 2, // Dual-worker pool
);

// Optional: Warmup for better performance
await isolateKit.warmup();
```

### 3. Run and Monitor

Use `runTask` to get a `TaskHandle`.

```dart
final handle = isolateKit.runTask(
  MyComputeTask(1000000),
  onProgress: (p) => print('Progress: ${(p.percentage * 100).toStringAsFixed(1)}%'),
);

try {
  final result = await handle.future;
  print('Result: $result');
} on TaskCancelledException {
  print('Task was cancelled');
} on TaskTimeoutException {
  print('Task timed out');
}
```

## 📚 Advanced Usage

### Isolate Pooling vs. Single Isolate

- **Single Isolate (`usePool: false`)**: Best for occasional tasks. Uses less memory.
- **Isolate Pool (`usePool: true`)**: Best for high-frequency tasks or multiple parallel operations. It automatically distributes tasks to the least busy worker.

```dart
// Run multiple tasks in parallel with a pool
final handles = [
  isolateKit.runTask(task1),
  isolateKit.runTask(task2),
  isolateKit.runTask(task3),
  isolateKit.runTask(task4),
];

final results = await Future.wait(
  handles.map((h) => h.future),
);
```

### Task Priority

`IsolateKit` uses a priority queue. High-priority tasks will "jump" ahead of low-priority ones in the queue.

```dart
class CriticalTask extends IsolateTask<dynamic, String> {
  @override
  int get priority => TaskPriority.critical; // Will be executed first
}

class BackgroundSyncTask extends IsolateTask<dynamic, String> {
  @override
  int get priority => TaskPriority.low; // Deferred until others finish
}
```

| Priority | Value | Use Case |
|----------|-------|----------|
| `TaskPriority.realtime` | 20 | Extremely urgent, time-sensitive tasks |
| `TaskPriority.critical` | 15 | Must be processed immediately |
| `TaskPriority.high` | 10 | Important but not blocking |
| `TaskPriority.normal` | 5 | Default priority |
| `TaskPriority.low` | 0 | Background tasks that can be deferred |

### Task Cancellation

```dart
final handle = isolateKit.runTask(myTask);

// Cancel after 5 seconds
Future.delayed(Duration(seconds: 5), () => handle.cancel());

try {
  final result = await handle.future;
} on TaskCancelledException {
  print('Task was cancelled');
}
```

### Global Cancellation

Need to stop everything? Use `cancelAll()`.

```dart
await isolateKit.cancelAll();
```

### Combine Cancellation Tokens

```dart
final userToken = CancellationToken();
final timeoutToken = CancellationToken();

// Task will be cancelled if ANY token is cancelled
final combined = CancellationToken.combine([userToken, timeoutToken]);
```

### Real-time Progress Tracking

```dart
class ImageProcessingTask extends IsolateTask<String, Uint8List> {
  @override
  Future<Uint8List> execute({
    void Function(TaskProgress)? sendProgress,
    CancellationToken? cancellationToken,
  }) async {
    sendProgress?.call(TaskProgress(percentage: 0.0, message: 'Loading image...'));
    final bytes = await loadImage();

    sendProgress?.call(TaskProgress(percentage: 0.5, message: 'Applying filters...'));
    final processed = await processImage(bytes);

    sendProgress?.call(TaskProgress(percentage: 1.0, message: 'Complete!'));
    return processed;
  }
}
```

### Zero-Copy Data Transfer

For very large `Uint8List` data, use `transferables` to avoid memory copying overhead.

```dart
class DataTransferTask extends IsolateTask<Uint8List, Uint8List> {
  final Uint8List data;

  DataTransferTask(this.data);

  @override
  List<TransferableTypedData>? get transferables => [
    TransferableTypedData.fromList([data])
  ];

  // ... implementation
}
```

## ⚙️ Configuration

| Parameter | Default | Description |
|-----------|---------|-------------|
| `maxConcurrentTasks` | `3` | Maximum tasks allowed to run simultaneously. |
| `usePool` | `false` | Enable/Disable Isolate Pooling. |
| `poolSize` | `2` | Number of workers in the pool. |
| `idleTimeout` | `5 min` | Time before an idle isolate is automatically killed. |
| `idleCheckInterval` | `1 min` | How often to check for idle status. |
| `debugName` | `'IsolateController'` | Label used in debug logs. |

## 📊 Monitoring & Status

```dart
final status = isolateKit.getStatus();
print('Active tasks:    ${status['activeTasks']}');
print('Queued tasks:    ${status['queuedTasks']}');
print('Total completed: ${status['totalCompleted']}');
print('Pool size:       ${status['poolStatus']?['poolSize']}');

// Monitor all instances at once
final allStatus = IsolateKit.getAllStatus();
print('Total instances: ${allStatus['totalInstances']}');
```

## 🛠️ Error Handling

```dart
try {
  final result = await handle.future;
} on TaskCancelledException catch (e) {
  print('Task ${e.taskId} was cancelled');
} on TaskTimeoutException catch (e) {
  print('Task ${e.taskId} timed out after ${e.timeout.inSeconds}s');
} catch (e, stackTrace) {
  print('Unexpected error: $e');
  print('Stack: $stackTrace');
}
```

## 🧹 Cleanup

```dart
// Dispose a single instance
await isolateKit.dispose();

// Dispose by name
IsolateKit.disposeInstance('main_worker');

// Dispose all instances (e.g., on app exit)
IsolateKit.disposeAll();

// Reset and reinitialize
await isolateKit.reset();
```

## 📱 Lifecycle Management

`IsolateKit` is smart about system resources:

- **App Paused**: Waits 30 seconds, then disposes if no active tasks remain.
- **App Detached**: Force-disposes all resources immediately.
- **App Resumed**: Ready to receive new tasks, re-spawns isolates on demand.

## ⚠️ Best Practices

1. **Warmup for critical paths**: Call `warmup()` at app startup to eliminate first-run latency.
2. **Use Pool for parallel work**: Set `usePool: true` when running multiple concurrent tasks.
3. **Always check cancellation**: Call `cancellationToken?.throwIfCancelled()` inside long loops.
4. **Never do heavy work on the UI thread**: Pass only parameters to tasks, generate large data inside `execute()`.
5. **Set priority wisely**: Reserve `realtime`/`critical` for user-facing operations only.
6. **Use realistic timeouts**: Too-short timeouts cause unnecessary isolate kills and re-spawns.
7. **Track progress on long tasks**: Use `sendProgress` so users know the app is working.

## 🤝 Contributing

Found a bug or have a feature request? Open an issue or submit a PR!

---
Built with ❤️ for the Flutter community.