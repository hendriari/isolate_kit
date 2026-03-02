## [1.0.1]

### Updated :

- Example usage

### Fixed :

- Queue on cancellation token

## [1.0.0]

### 🎉 Initial Release

The first stable release of IsolateKit - a powerful Flutter package for background task processing with Dart Isolates.

### Added

#### Core Features

- **Task Cancellation System**
    - `CancellationToken` with proper cleanup and listener support
    - Cancel handshake protocol between main and worker isolates
    - `throwIfCancelled()` method for graceful cancellation handling
    - Combined cancellation tokens for complex scenarios

- **Zero-Copy Data Transfer**
    - Support for `TransferableTypedData` for efficient large data transfer
    - Automatic memory optimization for data over 100KB
    - No memory copy overhead for binary data

- **Priority-Based Task Scheduling**
    - Five priority levels: `realtime`, `critical`, `high`, `normal`, `low`
    - Automatic task sorting by priority
    - FIFO ordering for tasks with the same priority
    - Configurable max concurrent tasks

#### Progress & Monitoring

- **Real-Time Progress Tracking**
    - Progress callbacks with percentage, message, and custom data
    - Timestamp tracking for all progress updates
    - Non-blocking progress reporting

- **Comprehensive Status Monitoring**
    - Per-instance status with detailed metrics
    - Global status for all instances
    - Queue details and worker metrics
    - Active/queued/completed task counters

#### Performance & Resource Management

- **Isolate Pooling**
    - Configurable pool size for optimal performance
    - Automatic load balancing across workers
    - Worker health monitoring and statistics
    - Pool-wide task distribution

- **Auto-Dispose & Lifecycle Management**
    - Configurable idle timeout (default: 5 minutes)
    - App lifecycle integration (paused/resumed/detached)
    - Automatic cleanup on app pause/detach
    - Manual disposal with force option

- **Warmup Support**
    - Pre-initialize isolates to eliminate first-call latency
    - Optional warmup for performance-critical applications
    - Background initialization without blocking

#### Reliability & Error Handling

- **Robust Error Handling**
    - Custom exception types: `TaskCancelledException`, `TaskTimeoutException`
    - Stack trace preservation for debugging
    - Isolate error recovery and restart
    - Timeout protection for long-running tasks

- **Type Safety**
    - Generic `IsolateTask<TCommand, TResult>` base class
    - Full type inference throughout the API
    - Compile-time type safety
    - `TaskHandle<T>` for type-safe task results

#### Developer Experience

- **Task Registry System**
    - Centralized task registration
    - Dynamic task creation
    - Registry cloning for isolate workers
    - Type-to-string mapping

- **Multiple Instance Support**
    - Singleton pattern with named instances via `IsolateKit.instance()`
    - Factory pattern for non-singleton instances via `IsolateKit.create()`
    - Instance management utilities (`disposeInstance`, `disposeAll`)
    - Per-instance configuration

- **Advanced Task Management**
    - Task metadata support for debugging
    - Estimated duration hints for better scheduling
    - Queue management with waiting time tracking
    - Task handle with cancellation and timeout support

### Technical Details

- **Dependencies**
    - `collection`: ^1.18.0 - For priority queue implementation
    - `synchronized`: ^3.1.0 - For thread-safe operations
    - `uuid`: ^4.0.0 - For unique task IDs

- **Platform Support**
    - Flutter: >=3.0.0
    - Dart: >=3.0.0

### Documentation

- Comprehensive README with examples
- API documentation for all public classes
- Best practices guide
- Error handling patterns

# [1.0.1]
updated:
- update example heavy task processing
- update initial timeout duration
- update cancel task and then return boolean value