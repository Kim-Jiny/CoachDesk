class MemberGroup {
  final String id;
  final String organizationId;
  final String name;
  final int sortOrder;

  const MemberGroup({
    required this.id,
    required this.organizationId,
    required this.name,
    required this.sortOrder,
  });

  factory MemberGroup.fromJson(Map<String, dynamic> json) {
    return MemberGroup(
      id: json['id'] as String,
      organizationId: json['organizationId'] as String,
      name: json['name'] as String,
      sortOrder: json['sortOrder'] as int? ?? 0,
    );
  }
}

class Member {
  final String id;
  final String organizationId;
  final String? memberGroupId;
  final String? memberGroupName;
  final int memberGroupSortOrder;
  final String name;
  final String? phone;
  final String? email;
  final DateTime? birthDate;
  final String? gender;
  final String? quickMemo;
  final String? memo;
  final String status;
  final String packageStatus;
  final String packageStatusLabel;
  final bool hasMemberAccount;
  final String memberSourceLabel;
  final String memberAccessLabel;
  final DateTime createdAt;

  const Member({
    required this.id,
    required this.organizationId,
    this.memberGroupId,
    this.memberGroupName,
    this.memberGroupSortOrder = 0,
    required this.name,
    this.phone,
    this.email,
    this.birthDate,
    this.gender,
    this.quickMemo,
    this.memo,
    required this.status,
    required this.packageStatus,
    required this.packageStatusLabel,
    required this.hasMemberAccount,
    required this.memberSourceLabel,
    required this.memberAccessLabel,
    required this.createdAt,
  });

  factory Member.fromJson(Map<String, dynamic> json) {
    return Member(
      id: json['id'] as String,
      organizationId: json['organizationId'] as String,
      memberGroupId: json['memberGroupId'] as String?,
      memberGroupName:
          (json['memberGroup'] as Map<String, dynamic>?)?['name'] as String?,
      memberGroupSortOrder:
          (json['memberGroup'] as Map<String, dynamic>?)?['sortOrder']
              as int? ??
          0,
      name: json['name'] as String,
      phone: json['phone'] as String?,
      email: json['email'] as String?,
      birthDate: json['birthDate'] != null
          ? DateTime.parse(json['birthDate'] as String)
          : null,
      gender: json['gender'] as String?,
      quickMemo: json['quickMemo'] as String?,
      memo: json['memo'] as String?,
      status: json['status'] as String? ?? 'ACTIVE',
      packageStatus: json['packageStatus'] as String? ?? 'GENERAL_MEMBER',
      packageStatusLabel: json['packageStatusLabel'] as String? ?? '일반 회원',
      hasMemberAccount: json['hasMemberAccount'] as bool? ?? false,
      memberSourceLabel: json['memberSourceLabel'] as String? ?? '관리자 등록 회원',
      memberAccessLabel: json['memberAccessLabel'] as String? ?? '채팅 미연동',
      createdAt: DateTime.parse(json['createdAt'] as String),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'memberGroupId': memberGroupId,
    'name': name,
    'phone': phone,
    'email': email,
    'birthDate': birthDate?.toIso8601String(),
    'gender': gender,
    'quickMemo': quickMemo,
    'memo': memo,
    'status': status,
    'packageStatus': packageStatus,
    'packageStatusLabel': packageStatusLabel,
    'hasMemberAccount': hasMemberAccount,
    'memberSourceLabel': memberSourceLabel,
    'memberAccessLabel': memberAccessLabel,
  };

  Member copyWith({
    String? name,
    String? phone,
    String? email,
    DateTime? birthDate,
    String? gender,
    String? quickMemo,
    String? memo,
    String? status,
    String? packageStatus,
    String? packageStatusLabel,
    bool? hasMemberAccount,
    String? memberSourceLabel,
    String? memberAccessLabel,
  }) {
    return Member(
      id: id,
      organizationId: organizationId,
      memberGroupId: memberGroupId,
      memberGroupName: memberGroupName,
      memberGroupSortOrder: memberGroupSortOrder,
      name: name ?? this.name,
      phone: phone ?? this.phone,
      email: email ?? this.email,
      birthDate: birthDate ?? this.birthDate,
      gender: gender ?? this.gender,
      quickMemo: quickMemo ?? this.quickMemo,
      memo: memo ?? this.memo,
      status: status ?? this.status,
      packageStatus: packageStatus ?? this.packageStatus,
      packageStatusLabel: packageStatusLabel ?? this.packageStatusLabel,
      hasMemberAccount: hasMemberAccount ?? this.hasMemberAccount,
      memberSourceLabel: memberSourceLabel ?? this.memberSourceLabel,
      memberAccessLabel: memberAccessLabel ?? this.memberAccessLabel,
      createdAt: createdAt,
    );
  }
}
