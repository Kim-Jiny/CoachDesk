class Organization {
  final String id;
  final String name;
  final String? description;
  final String inviteCode;
  final String? role;
  final String bookingMode;
  final String reservationPolicy;
  final String? reservationNoticeText;
  final String? reservationNoticeImageUrl;
  final int reservationOpenDaysBefore;
  final int reservationOpenHoursBefore;
  final int reservationCancelDeadlineMinutes;

  const Organization({
    required this.id,
    required this.name,
    this.description,
    required this.inviteCode,
    this.role,
    this.bookingMode = 'PRIVATE',
    this.reservationPolicy = 'AUTO_CONFIRM',
    this.reservationNoticeText,
    this.reservationNoticeImageUrl,
    this.reservationOpenDaysBefore = 30,
    this.reservationOpenHoursBefore = 0,
    this.reservationCancelDeadlineMinutes = 120,
  });

  factory Organization.fromJson(Map<String, dynamic> json) {
    return Organization(
      id: json['id'] as String,
      name: json['name'] as String,
      description: json['description'] as String?,
      inviteCode: json['inviteCode'] as String,
      role: json['role'] as String?,
      bookingMode: json['bookingMode'] as String? ?? 'PRIVATE',
      reservationPolicy: json['reservationPolicy'] as String? ?? 'AUTO_CONFIRM',
      reservationNoticeText: json['reservationNoticeText'] as String?,
      reservationNoticeImageUrl: json['reservationNoticeImageUrl'] as String?,
      reservationOpenDaysBefore:
          json['reservationOpenDaysBefore'] as int? ?? 30,
      reservationOpenHoursBefore:
          json['reservationOpenHoursBefore'] as int? ?? 0,
      reservationCancelDeadlineMinutes:
          json['reservationCancelDeadlineMinutes'] as int? ?? 120,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'description': description,
    'inviteCode': inviteCode,
    'role': role,
    'bookingMode': bookingMode,
    'reservationPolicy': reservationPolicy,
    'reservationNoticeText': reservationNoticeText,
    'reservationNoticeImageUrl': reservationNoticeImageUrl,
    'reservationOpenDaysBefore': reservationOpenDaysBefore,
    'reservationOpenHoursBefore': reservationOpenHoursBefore,
    'reservationCancelDeadlineMinutes': reservationCancelDeadlineMinutes,
  };
}
