class TaskProgress {
  final double percentage;
  final String? message;
  final Map<String, dynamic>? data;
  final DateTime timestamp;

  TaskProgress({
    required this.percentage,
    this.message,
    this.data,
  }) : timestamp = DateTime.now();

  @override
  String toString() =>
      'Progress: ${(percentage * 100).toStringAsFixed(1)}%${message != null ? ' - $message' : ''}';

  Map<String, dynamic> toJson() => {
        'percentage': percentage,
        'message': message,
        'data': data,
        'timestamp': timestamp.toIso8601String(),
      };
}
