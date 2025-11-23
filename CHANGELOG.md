## 1.0.0 Initial Release 🎉

### Added

1. ✅ True Task Cancellation with CancellationToken

    * Proper cleanup and listener support
    * Cancel handshake protocol between main and worker isolates
    * throwIfCancelled() for graceful cancellation

2. ✅ Zero-Copy Data Transfer with TransferableTypedData

    * TransferableHelper utility class
    * Automatic threshold detection (100KB)
    * Efficient transfer of large data without memory copy

3. ✅ Priority Queue System

    * 5 priority levels: realtime, critical, high, normal, low
    * Automatic task sorting
    * FIFO for same-priority tasks

4. ✅ Progress Callbacks

    * Real-time progress updates
    * Percentage, message, and custom data support
    * Timestamp tracking

5. ✅ Isolate Pooling

    * Configurable pool size
    * Load balancing across workers
    * Worker status monitoring

6. ✅ Auto-Dispose

    * Idle timeout (default: 5 minutes)
    * App lifecycle integration
    * Automatic cleanup on app pause/detach

7. ✅ Warmup Support

    * Pre-initialize isolates
    * Eliminate first-call latency
    * Optional feature

8. ✅ Crash-Resistant Error Handling

    * Proper exception types (TaskCancelledException, TaskTimeoutException)
    * Stack trace preservation
    * Isolate error recovery

9. ✅ Type-Safe Generic Support

    * IsolateTask<TCommand, TResult>
    * Full type inference
    * Compile-time safety

10. ✅ Advanced Task Management

    * Max concurrent tasks limit
    * Task queueing with metadata
    * Running task tracking

11. ✅ Multiple Instance Support

    * Singleton pattern with named instances
    * Factory pattern for non-singleton
    * Instance management utilities

12. ✅ Comprehensive Status Monitoring

    * Per-instance status
    * Global status for all instances
    * Queue details and worker metrics

13. ✅ Lifecycle Management

    * App lifecycle observer
    * Automatic disposal on app detach
    * Manual dispose with force option
