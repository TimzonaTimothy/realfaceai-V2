class MaintenanceInfo {
  final String message;
  final int retryAfter; // seconds — hint for auto-retry countdown

  // Scheduled maintenance fields (optional — backend may omit them)
  final DateTime? scheduledStart; // UTC — when maintenance begins
  final DateTime? scheduledEnd; // UTC — when maintenance is expected to end
  final String? title; // e.g. "Scheduled Maintenance"

  const MaintenanceInfo({
    required this.message,
    required this.retryAfter,
    this.scheduledStart,
    this.scheduledEnd,
    this.title,
  });

  factory MaintenanceInfo.fromJson(Map<String, dynamic> json) {
    DateTime? parseUtc(dynamic val) {
      if (val == null) return null;
      try {
        return DateTime.parse(val as String).toLocal();
      } catch (_) {
        return null;
      }
    }

    return MaintenanceInfo(
      message: json['message'] as String? ??
          'We are under maintenance. Please check back soon.',
      retryAfter: json['retry_after'] as int? ?? 3600,
      title: json['title'] as String?,
      scheduledStart: parseUtc(json['scheduled_start']),
      scheduledEnd: parseUtc(json['scheduled_end']),
    );
  }

  /// True when the backend has told us exactly when maintenance will end.
  bool get hasSchedule => scheduledStart != null || scheduledEnd != null;

  /// Remaining duration until scheduled end. Null if no end time provided.
  Duration? get timeUntilEnd {
    if (scheduledEnd == null) return null;
    final diff = scheduledEnd!.difference(DateTime.now());
    return diff.isNegative ? Duration.zero : diff;
  }
}
