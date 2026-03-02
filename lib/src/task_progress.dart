/// Represents the progress of a background task.
class TaskProgress {
  /// Progress percentage ranging from 0.0 to 1.0.
  final double percentage;

  /// Optional message providing additional context for the progress.
  final String? message;

  /// Optional map of data containing more detailed progress information.
  final Map<String, dynamic>? data;

  /// Timestamp when this progress update was created.
  final DateTime timestamp;

  /// Creates a [TaskProgress] update.
  TaskProgress({
    required this.percentage,
    this.message,
    this.data,
  }) : timestamp = DateTime.now();

  @override
  String toString() =>
      'Progress: ${(percentage * 100).toStringAsFixed(1)}%${message != null ? ' - $message' : ''}';

  /// Converts the progress update to a JSON-compatible map.
  Map<String, dynamic> toJson() => {
        'percentage': percentage,
        'message': message,
        'data': data,
        'timestamp': timestamp.toIso8601String(),
      };
}
