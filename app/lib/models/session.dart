class Session {
  final String id;
  final String organizationId;
  final String reservationId;
  final String coachId;
  final String memberId;
  final String? memberPackageId;
  final DateTime date;
  final String attendance;
  final String? memo;
  final dynamic workoutRecords;
  final String? feedback;
  final String? memberName;
  final String? coachName;
  final String? startTime;
  final String? endTime;

  const Session({
    required this.id,
    required this.organizationId,
    required this.reservationId,
    required this.coachId,
    required this.memberId,
    this.memberPackageId,
    required this.date,
    required this.attendance,
    this.memo,
    this.workoutRecords,
    this.feedback,
    this.memberName,
    this.coachName,
    this.startTime,
    this.endTime,
  });

  factory Session.fromJson(Map<String, dynamic> json) {
    return Session(
      id: json['id'] as String,
      organizationId: json['organizationId'] as String,
      reservationId: json['reservationId'] as String,
      coachId: json['coachId'] as String,
      memberId: json['memberId'] as String,
      memberPackageId: json['memberPackageId'] as String?,
      date: DateTime.parse(json['date'] as String),
      attendance: json['attendance'] as String? ?? 'PRESENT',
      memo: json['memo'] as String?,
      workoutRecords: json['workoutRecords'],
      feedback: json['feedback'] as String?,
      memberName: json['member']?['name'] as String?,
      coachName: json['coach']?['name'] as String?,
      startTime: json['reservation']?['startTime'] as String?,
      endTime: json['reservation']?['endTime'] as String?,
    );
  }
}
