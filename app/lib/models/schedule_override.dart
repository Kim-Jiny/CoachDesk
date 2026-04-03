class ScheduleOverride {
  final String id;
  final String organizationId;
  final String coachId;
  final DateTime date;
  final String type; // OPEN | CLOSED
  final String? startTime;
  final String? endTime;
  final int? slotDuration;
  final int? breakMinutes;
  final int? maxCapacity;
  final String? coachName;
  final DateTime createdAt;

  const ScheduleOverride({
    required this.id,
    required this.organizationId,
    required this.coachId,
    required this.date,
    required this.type,
    this.startTime,
    this.endTime,
    this.slotDuration,
    this.breakMinutes,
    this.maxCapacity,
    this.coachName,
    required this.createdAt,
  });

  static DateTime _parseDateOnly(String raw) {
    final dateOnly = raw.length >= 10 ? raw.substring(0, 10) : raw;
    return DateTime.parse(dateOnly);
  }

  factory ScheduleOverride.fromJson(Map<String, dynamic> json) {
    return ScheduleOverride(
      id: json['id'] as String,
      organizationId: json['organizationId'] as String,
      coachId: json['coachId'] as String,
      date: _parseDateOnly(json['date'] as String),
      type: json['type'] as String,
      startTime: json['startTime'] as String?,
      endTime: json['endTime'] as String?,
      slotDuration: json['slotDuration'] as int?,
      breakMinutes: json['breakMinutes'] as int?,
      maxCapacity: json['maxCapacity'] as int?,
      coachName: (json['coach'] as Map<String, dynamic>?)?['name'] as String?,
      createdAt: DateTime.parse(json['createdAt'] as String),
    );
  }
}
