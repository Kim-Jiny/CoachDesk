class MemberSlot {
  final String coachId;
  final String coachName;
  final String startTime;
  final String endTime;
  final bool available;

  const MemberSlot({
    required this.coachId,
    required this.coachName,
    required this.startTime,
    required this.endTime,
    required this.available,
  });

  factory MemberSlot.fromJson(Map<String, dynamic> json) {
    return MemberSlot(
      coachId: json['coachId'] as String,
      coachName: json['coachName'] as String? ?? '',
      startTime: json['startTime'] as String,
      endTime: json['endTime'] as String,
      available: json['available'] as bool? ?? false,
    );
  }
}

class MemberReservationSummary {
  final String id;
  final String organizationId;
  final String organizationName;
  final String coachId;
  final String coachName;
  final DateTime date;
  final String startTime;
  final String endTime;
  final String status;

  const MemberReservationSummary({
    required this.id,
    required this.organizationId,
    required this.organizationName,
    required this.coachId,
    required this.coachName,
    required this.date,
    required this.startTime,
    required this.endTime,
    required this.status,
  });

  factory MemberReservationSummary.fromJson(Map<String, dynamic> json) {
    final rawDate = json['date'] as String;
    final dateOnly = rawDate.length >= 10 ? rawDate.substring(0, 10) : rawDate;
    return MemberReservationSummary(
      id: json['id'] as String,
      organizationId: json['organizationId'] as String,
      organizationName: json['organizationName'] as String? ?? '',
      coachId: json['coachId'] as String,
      coachName: json['coachName'] as String? ?? '',
      date: DateTime.parse(dateOnly),
      startTime: json['startTime'] as String,
      endTime: json['endTime'] as String,
      status: json['status'] as String,
    );
  }
}
