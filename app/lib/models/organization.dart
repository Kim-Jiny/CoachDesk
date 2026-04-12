class Organization {
  final String id;
  final String name;
  final String? description;
  final String inviteCode;
  final String? role;
  final int? memberCount;
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
    this.memberCount,
    this.bookingMode = 'PRIVATE',
    this.reservationPolicy = 'AUTO_CONFIRM',
    this.reservationNoticeText,
    this.reservationNoticeImageUrl,
    this.reservationOpenDaysBefore = 30,
    this.reservationOpenHoursBefore = 0,
    this.reservationCancelDeadlineMinutes = 120,
  });

  bool get isOwner => role == 'OWNER';
  bool get isManager => role == 'MANAGER';
  bool get isStaff => role == 'STAFF';
  bool get isViewer => role == 'VIEWER';
  bool get canManageMembers => role == 'OWNER' || role == 'MANAGER';
  bool get canManagePackages => role == 'OWNER' || role == 'MANAGER';

  factory Organization.fromJson(Map<String, dynamic> json) {
    return Organization(
      id: json['id'] as String,
      name: json['name'] as String,
      description: json['description'] as String?,
      inviteCode: json['inviteCode'] as String? ?? '',
      role: json['role'] as String?,
      memberCount: json['memberCount'] as int?,
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
    'memberCount': memberCount,
    'bookingMode': bookingMode,
    'reservationPolicy': reservationPolicy,
    'reservationNoticeText': reservationNoticeText,
    'reservationNoticeImageUrl': reservationNoticeImageUrl,
    'reservationOpenDaysBefore': reservationOpenDaysBefore,
    'reservationOpenHoursBefore': reservationOpenHoursBefore,
    'reservationCancelDeadlineMinutes': reservationCancelDeadlineMinutes,
  };
}

class CenterJoinRequest {
  final String id;
  final String organizationId;
  final String organizationName;
  final String status;
  final String? message;
  final String createdAt;

  const CenterJoinRequest({
    required this.id,
    required this.organizationId,
    required this.organizationName,
    required this.status,
    this.message,
    required this.createdAt,
  });

  factory CenterJoinRequest.fromJson(Map<String, dynamic> json) {
    return CenterJoinRequest(
      id: json['id'] as String,
      organizationId: json['organizationId'] as String,
      organizationName: json['organizationName'] as String? ?? '',
      status: json['status'] as String,
      message: json['message'] as String?,
      createdAt: json['createdAt'] as String? ?? '',
    );
  }
}
