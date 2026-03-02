/// Standard priority levels for background tasks.
///
/// Tasks with higher priority values are prioritized in the execution queue.
class TaskPriority {
  /// Low priority for non-essential background tasks.
  static const int low = 0;

  /// Normal priority for typical background tasks.
  static const int normal = 5;

  /// High priority for tasks that the user is actively waiting for.
  static const int high = 10;

  /// Critical priority for tasks that impact immediate app stability or responsiveness.
  static const int critical = 15;

  /// Realtime priority for tasks that must be executed as soon as possible.
  static const int realtime = 20;
}
