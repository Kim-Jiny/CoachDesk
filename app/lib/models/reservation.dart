class Reservation {
  final String id;
  final String organizationId;
  final String coachId;
  final String memberId;
  final DateTime date;
  final String startTime;
  final String endTime;
  final String status;
  final String? quickMemo;
  final String? memberQuickMemo;
  final String? memo;
  final int delayMinutes;
  final String? originalStartTime;
  final String? originalEndTime;
  final String? memberName;
  final String? coachName;
  final bool isMemberBooked;

  const Reservation({
    required this.id,
    required this.organizationId,
    required this.coachId,
    required this.memberId,
    required this.date,
    required this.startTime,
    required this.endTime,
    required this.status,
    this.quickMemo,
    this.memberQuickMemo,
    this.memo,
    this.delayMinutes = 0,
    this.originalStartTime,
    this.originalEndTime,
    this.memberName,
    this.coachName,
    this.isMemberBooked = false,
  });

  static DateTime _parseDateOnly(String raw) {
    final dateOnly = raw.length >= 10 ? raw.substring(0, 10) : raw;
    return DateTime.parse(dateOnly);
  }

  factory Reservation.fromJson(Map<String, dynamic> json) {
    final member = json['member'] as Map<String, dynamic>?;
    return Reservation(
      id: json['id'] as String,
      organizationId: json['organizationId'] as String,
      coachId: json['coachId'] as String,
      memberId: json['memberId'] as String,
      date: _parseDateOnly(json['date'] as String),
      startTime: json['startTime'] as String,
      endTime: json['endTime'] as String,
      status: json['status'] as String,
      quickMemo: json['quickMemo'] as String?,
      memberQuickMemo: json['memberQuickMemo'] as String?,
      memo: json['memo'] as String?,
      delayMinutes: json['delayMinutes'] as int? ?? 0,
      originalStartTime: json['originalStartTime'] as String?,
      originalEndTime: json['originalEndTime'] as String?,
      memberName: member?['name'] as String?,
      coachName: json['coach']?['name'] as String?,
      isMemberBooked: member?['memberAccountId'] != null,
    );
  }

  Map<String, dynamic> toJson() => {
    'memberId': memberId,
    'date': date.toIso8601String().split('T')[0],
    'startTime': startTime,
    'endTime': endTime,
    'quickMemo': quickMemo,
    'memberQuickMemo': memberQuickMemo,
    'memo': memo,
    'delayMinutes': delayMinutes,
    'originalStartTime': originalStartTime,
    'originalEndTime': originalEndTime,
  };
}
