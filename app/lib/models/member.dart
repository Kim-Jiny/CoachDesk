class Member {
  final String id;
  final String organizationId;
  final String name;
  final String? phone;
  final String? email;
  final DateTime? birthDate;
  final String? gender;
  final String? quickMemo;
  final String? memo;
  final String status;
  final DateTime createdAt;

  const Member({
    required this.id,
    required this.organizationId,
    required this.name,
    this.phone,
    this.email,
    this.birthDate,
    this.gender,
    this.quickMemo,
    this.memo,
    required this.status,
    required this.createdAt,
  });

  factory Member.fromJson(Map<String, dynamic> json) {
    return Member(
      id: json['id'] as String,
      organizationId: json['organizationId'] as String,
      name: json['name'] as String,
      phone: json['phone'] as String?,
      email: json['email'] as String?,
      birthDate: json['birthDate'] != null ? DateTime.parse(json['birthDate'] as String) : null,
      gender: json['gender'] as String?,
      quickMemo: json['quickMemo'] as String?,
      memo: json['memo'] as String?,
      status: json['status'] as String? ?? 'ACTIVE',
      createdAt: DateTime.parse(json['createdAt'] as String),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'phone': phone,
    'email': email,
    'birthDate': birthDate?.toIso8601String(),
    'gender': gender,
    'quickMemo': quickMemo,
    'memo': memo,
    'status': status,
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
  }) {
    return Member(
      id: id,
      organizationId: organizationId,
      name: name ?? this.name,
      phone: phone ?? this.phone,
      email: email ?? this.email,
      birthDate: birthDate ?? this.birthDate,
      gender: gender ?? this.gender,
      quickMemo: quickMemo ?? this.quickMemo,
      memo: memo ?? this.memo,
      status: status ?? this.status,
      createdAt: createdAt,
    );
  }
}
