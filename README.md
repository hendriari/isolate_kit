# IsolateKit 🚀

A powerful and easy-to-use Flutter package for running heavy tasks in the background using Dart Isolates with support for cancellation, progress tracking, task prioritization, and pooling.

## ✨ Key Features

- **🔄 Background Processing**: Run heavy tasks without blocking the UI thread
- **⚡ Isolate Pooling**: Manage multiple isolates for optimal performance
- **🎯 Task Priority**: Control task execution priority (realtime, critical, high, normal, low)
- **📊 Progress Tracking**: Monitor task progress in real-time
- **🚫 Cancellation Support**: Cancel tasks at any time with CancellationToken
- **⏱️ Timeout Handling**: Automatic timeout for long-running tasks
- **🔥 Warmup Mode**: Pre-initialize isolates to reduce latency
- **♻️ Auto Resource Management**: Automatically dispose isolates when idle
- **📱 Lifecycle Aware**: Responsive to application lifecycle changes
- **🎨 Type-Safe**: Fully type-safe with generic support

## 📦 Installation

Add to your `pubspec.yaml`:

```yaml
dependencies:
  isolate_kit: ^1.0.0
```

## 🚀 Quick Start

### 1. Create a Task Class

```dart
class HeavyComputationTask extends IsolateTask<Map<String, dynamic>, int> {
  final Map<String, dynamic> _payload;

  HeavyComputationTask(this._payload);

  @override
  Map<String, dynamic> get command => _payload;

  @override
  Map<String, dynamic> get payload => _payload;

  @override
  int get priority => TaskPriority.high;

  @override
  Future<int> execute({
    void Function(TaskProgress)? sendProgress,
    CancellationToken? cancellationToken,
  }) async {
    final iterations = _payload['iterations'] as int;
    int result = 0;

    for (int i = 0; i < iterations; i++) {
      // Check for cancellation
      cancellationToken?.throwIfCancelled();

      // Heavy computation
      result += i * 2;

      // Report progress
      if (i % 100 == 0) {
        sendProgress?.call(TaskProgress(
          percentage: i / iterations,
          message: 'Processing $i/$iterations',
        ));
      }
    }

    return result;
  }
}
```

### 2. Register the Task

```dart
final registry = IsolateTaskRegistry();

registry.register<HeavyComputationTask>(
  'HeavyComputationTask',
  (payload, transferables) => HeavyComputationTask(payload),
);
```

### 3. Initialize IsolateKit

```dart
final isolateKit = IsolateKit.instance(
  name: 'main',
  taskRegistry: registry,
  maxConcurrentTasks: 3,
  usePool: true,
  poolSize: 2,
);

// Optional: Warmup for better performance
await isolateKit.warmup();
```

### 4. Run a Task

```dart
final task = HeavyComputationTask({'iterations': 10000});

final handle = isolateKit.runTask(
  task,
  timeout: Duration(seconds: 30),
  onProgress: (progress) {
    print('Progress: ${progress.percentage * 100}% - ${progress.message}');
  },
);

try {
  final result = await handle.future;
  print('Result: $result');
} on TaskCancelledException {
  print('Task cancelled');
} on TaskTimeoutException {
  print('Task timeout');
} catch (e) {
  print('Error: $e');
}
```

## 📚 Usage Examples

### Task with Progress Tracking

```dart
class ImageProcessingTask extends IsolateTask<String, Uint8List> {
  final String imagePath;

  ImageProcessingTask(this.imagePath);

  @override
  String get command => imagePath;

  @override
  Map<String, dynamic> get payload => {'path': imagePath};

  @override
  Future<Uint8List> execute({
    void Function(TaskProgress)? sendProgress,
    CancellationToken? cancellationToken,
  }) async {
    sendProgress?.call(TaskProgress(
      percentage: 0.0,
      message: 'Loading image...',
    ));

    // Load image
    final bytes = await loadImage(imagePath);
    
    sendProgress?.call(TaskProgress(
      percentage: 0.5,
      message: 'Processing...',
    ));

    // Process image
    final processed = await processImage(bytes);
    
    sendProgress?.call(TaskProgress(
      percentage: 1.0,
      message: 'Complete',
    ));

    return processed;
  }
}
```

### Task with Priority

```dart
class RealtimeTask extends IsolateTask<dynamic, String> {
  @override
  int get priority => TaskPriority.realtime; // Highest priority
  
  // ... implementation
}

class BackgroundTask extends IsolateTask<dynamic, String> {
  @override
  int get priority => TaskPriority.low; // Lowest priority
  
  // ... implementation
}
```

### Task Cancellation

```dart
final handle = isolateKit.runTask(myTask);

// Cancel after 5 seconds
Future.delayed(Duration(seconds: 5), () {
  handle.cancel();
});

try {
  await handle.future;
} on TaskCancelledException {
  print('Task was cancelled');
}
```

### Multiple Tasks with Pool

```dart
final isolateKit = IsolateKit.instance(
  name: 'pool',
  taskRegistry: registry,
  usePool: true,
  poolSize: 4, // 4 isolates in the pool
  maxConcurrentTasks: 8,
);

// Run multiple tasks in parallel
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

## 🎯 Task Priority Levels

```dart
TaskPriority.realtime  // 20 - For extremely urgent tasks
TaskPriority.critical  // 15 - Important tasks that must be processed immediately
TaskPriority.high      // 10 - High priority tasks
TaskPriority.normal    // 5  - Default priority
TaskPriority.low       // 0  - Background tasks that can be deferred
```

## ⚙️ Configuration

```dart
IsolateKit.instance(
  name: 'myInstance',
  taskRegistry: registry,
  
  // Performance
  maxConcurrentTasks: 3,        // Maximum tasks running simultaneously
  usePool: true,                 // Use isolate pool
  poolSize: 2,                   // Number of isolates in the pool
  
  // Resource Management
  idleTimeout: Duration(minutes: 5),        // Auto dispose when idle
  idleCheckInterval: Duration(minutes: 1),  // Idle check interval
  
  // Debugging
  debugName: 'MyIsolateKit',
);
```

## 📊 Monitoring & Status

```dart
// Instance status
final status = isolateKit.getStatus();
print('Active tasks: ${status['activeTasks']}');
print('Queued tasks: ${status['queuedTasks']}');
print('Total completed: ${status['totalCompleted']}');

// All instances status
final allStatus = IsolateKit.getAllStatus();
print('Total instances: ${allStatus['totalInstances']}');
```

## 🛠️ Advanced Features

### Custom Transferables (Zero-Copy)

```dart
class DataTransferTask extends IsolateTask<Uint8List, Uint8List> {
  final Uint8List data;

  @override
  List<TransferableTypedData>? get transferables => [
    TransferableTypedData.fromList([data])
  ];
  
  // ... implementation
}
```

### Combine Cancellation Tokens

```dart
final token1 = CancellationToken();
final token2 = CancellationToken();

final combined = CancellationToken.combine([token1, token2]);
// Task will be cancelled if ANY token is cancelled
```

### Task Metadata

```dart
class MyTask extends IsolateTask<dynamic, dynamic> {
  @override
  Duration? get estimatedDuration => Duration(seconds: 10);
  
  @override
  Map<String, dynamic> get metadata => {
    'version': '1.0',
    'author': 'Me',
  };
}
```

## 🧹 Cleanup

```dart
// Dispose single instance
await isolateKit.dispose();

// Dispose by name
IsolateKit.disposeInstance('myInstance');

// Dispose all instances
IsolateKit.disposeAll();

// Reset instance
await isolateKit.reset();
```

## ⚠️ Best Practices

1. **Warmup for critical tasks**: Call `warmup()` at app startup for optimal performance
2. **Use Pool for many tasks**: Set `usePool: true` when frequently running tasks
3. **Set priority wisely**: Use priorities according to task requirements
4. **Handle cancellation**: Always check `cancellationToken` in long loops
5. **Monitor progress**: Use `sendProgress` for long-running tasks
6. **Set realistic timeouts**: Avoid timeouts that are too short
7. **Dispose when unused**: Let auto-dispose work or manually dispose

## 🐛 Error Handling

```dart
try {
  final result = await handle.future;
} on TaskCancelledException catch (e) {
  print('Task ${e.taskId} was cancelled');
} on TaskTimeoutException catch (e) {
  print('Task ${e.taskId} timed out after ${e.timeout}');
} catch (e, stackTrace) {
  print('Error: $e');
  print('Stack: $stackTrace');
}
```

## 📱 Lifecycle Management

IsolateKit automatically handles application lifecycle:

- **App Paused**: Attempts to dispose if no active tasks
- **App Detached**: Force disposes all resources
- **App Resumed**: Ready to receive new tasks

## 🤝 Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

