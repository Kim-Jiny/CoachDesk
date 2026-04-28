class Package {
  final String id;
  final String organizationId;
  final String? coachId;
  final String? coachName;
  final String scope;
  final String name;
  final int totalSessions;
  final int price;
  final int? validDays;
  final bool isActive;
  final bool isPublic;
  final int activeMemberCount;
  final int totalUsedSessions;
  final DateTime createdAt;

  const Package({
    required this.id,
    required this.organizationId,
    this.coachId,
    this.coachName,
    this.scope = 'CENTER',
    required this.name,
    required this.totalSessions,
    required this.price,
    this.validDays,
    required this.isActive,
    required this.isPublic,
    this.activeMemberCount = 0,
    this.totalUsedSessions = 0,
    required this.createdAt,
  });

  factory Package.fromJson(Map<String, dynamic> json) {
    return Package(
      id: json['id'] as String,
      organizationId: json['organizationId'] as String,
      coachId: json['coachId'] as String?,
      coachName:
          json['coachName'] as String? ??
          (json['coach'] as Map<String, dynamic>?)?['name'] as String?,
      scope:
          json['scope'] as String? ??
          (json['coachId'] == null ? 'CENTER' : 'ADMIN'),
      name: json['name'] as String,
      totalSessions: json['totalSessions'] as int,
      price: json['price'] as int,
      validDays: json['validDays'] as int?,
      isActive: json['isActive'] as bool? ?? true,
      isPublic: json['isPublic'] as bool? ?? false,
      activeMemberCount: json['activeMemberCount'] as int? ?? 0,
      totalUsedSessions: json['totalUsedSessions'] as int? ?? 0,
      createdAt: DateTime.parse(json['createdAt'] as String),
    );
  }

  Map<String, dynamic> toJson() => {
    'name': name,
    'totalSessions': totalSessions,
    'price': price,
    'validDays': validDays,
    'isActive': isActive,
    'isPublic': isPublic,
    'scope': scope,
  };

  bool get isAdminScoped => scope == 'ADMIN';
  String get scopeLabel => isAdminScoped ? '관리자 패키지' : '센터 패키지';
}

class MemberPackage {
  final String id;
  final String memberId;
  final String packageId;
  final int totalSessions;
  final int usedSessions;
  final int remainingSessions;
  final DateTime purchaseDate;
  final DateTime? expiryDate;
  final int paidAmount;
  final String paymentMethod;
  final String status;
  final DateTime? pauseStartDate;
  final DateTime? pauseEndDate;
  final DateTime? pauseRequestedStartDate;
  final DateTime? pauseRequestedEndDate;
  final String pauseRequestStatus;
  final String? pauseRequestReason;
  final int pauseExtensionDays;
  final String? organizationName;
  final String? memberName;
  final Package? package;

  const MemberPackage({
    required this.id,
    required this.memberId,
    required this.packageId,
    required this.totalSessions,
    required this.usedSessions,
    required this.remainingSessions,
    required this.purchaseDate,
    this.expiryDate,
    required this.paidAmount,
    required this.paymentMethod,
    required this.status,
    this.pauseStartDate,
    this.pauseEndDate,
    this.pauseRequestedStartDate,
    this.pauseRequestedEndDate,
    this.pauseRequestStatus = 'NONE',
    this.pauseRequestReason,
    this.pauseExtensionDays = 0,
    this.organizationName,
    this.memberName,
    this.package,
  });

  bool get isCurrentlyPaused {
    if (pauseStartDate == null || pauseEndDate == null) return false;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final start = DateTime(
      pauseStartDate!.year,
      pauseStartDate!.month,
      pauseStartDate!.day,
    );
    final end = DateTime(
      pauseEndDate!.year,
      pauseEndDate!.month,
      pauseEndDate!.day,
    );
    return !today.isBefore(start) && !today.isAfter(end);
  }

  bool get hasPendingPauseRequest => pauseRequestStatus == 'PENDING';

  factory MemberPackage.fromJson(Map<String, dynamic> json) {
    return MemberPackage(
      id: json['id'] as String,
      memberId: json['memberId'] as String,
      packageId: json['packageId'] as String,
      totalSessions: json['totalSessions'] as int,
      usedSessions: json['usedSessions'] as int,
      remainingSessions: json['remainingSessions'] as int,
      purchaseDate: DateTime.parse(json['purchaseDate'] as String),
      expiryDate: json['expiryDate'] != null
          ? DateTime.parse(json['expiryDate'] as String)
          : null,
      paidAmount: json['paidAmount'] as int,
      paymentMethod: json['paymentMethod'] as String? ?? 'CASH',
      status: json['status'] as String? ?? 'ACTIVE',
      pauseStartDate: json['pauseStartDate'] != null
          ? DateTime.parse(json['pauseStartDate'] as String)
          : null,
      pauseEndDate: json['pauseEndDate'] != null
          ? DateTime.parse(json['pauseEndDate'] as String)
          : null,
      pauseRequestedStartDate: json['pauseRequestedStartDate'] != null
          ? DateTime.parse(json['pauseRequestedStartDate'] as String)
          : null,
      pauseRequestedEndDate: json['pauseRequestedEndDate'] != null
          ? DateTime.parse(json['pauseRequestedEndDate'] as String)
          : null,
      pauseRequestStatus: json['pauseRequestStatus'] as String? ?? 'NONE',
      pauseRequestReason: json['pauseRequestReason'] as String?,
      pauseExtensionDays: json['pauseExtensionDays'] as int? ?? 0,
      organizationName:
          (json['organization'] as Map<String, dynamic>?)?['name'] as String?,
      memberName: (json['member'] as Map<String, dynamic>?)?['name'] as String?,
      package: json['package'] != null
          ? Package.fromJson(json['package'] as Map<String, dynamic>)
          : null,
    );
  }
}

class MemberPackageAdjustment {
  final String id;
  final String type;
  final int sessionDelta;
  final DateTime? expiryDateBefore;
  final DateTime? expiryDateAfter;
  final String? reason;
  final String adminId;
  final String adminName;
  final DateTime createdAt;

  const MemberPackageAdjustment({
    required this.id,
    required this.type,
    required this.sessionDelta,
    this.expiryDateBefore,
    this.expiryDateAfter,
    this.reason,
    required this.adminId,
    required this.adminName,
    required this.createdAt,
  });

  factory MemberPackageAdjustment.fromJson(Map<String, dynamic> json) {
    return MemberPackageAdjustment(
      id: json['id'] as String,
      type: json['type'] as String,
      sessionDelta: json['sessionDelta'] as int? ?? 0,
      expiryDateBefore: json['expiryDateBefore'] != null
          ? DateTime.parse(json['expiryDateBefore'] as String)
          : null,
      expiryDateAfter: json['expiryDateAfter'] != null
          ? DateTime.parse(json['expiryDateAfter'] as String)
          : null,
      reason: json['reason'] as String?,
      adminId: json['adminId'] as String,
      adminName: json['adminName'] as String? ?? '',
      createdAt: DateTime.parse(json['createdAt'] as String),
    );
  }

  String get typeLabel => switch (type) {
        'EXTEND_EXPIRY' => '만료일 연장',
        'SHORTEN_EXPIRY' => '만료일 단축',
        'ADD_SESSIONS' => '회차 추가',
        'DEDUCT_SESSIONS' => '회차 차감',
        _ => type,
      };

  bool get isSessionAdjustment =>
      type == 'ADD_SESSIONS' || type == 'DEDUCT_SESSIONS';
}

class MemberPackageSessionEntry {
  final String id;
  final DateTime date;
  final String? startTime;
  final String? endTime;
  final String coachId;
  final String coachName;
  final String attendance;

  const MemberPackageSessionEntry({
    required this.id,
    required this.date,
    this.startTime,
    this.endTime,
    required this.coachId,
    required this.coachName,
    required this.attendance,
  });

  factory MemberPackageSessionEntry.fromJson(Map<String, dynamic> json) {
    return MemberPackageSessionEntry(
      id: json['id'] as String,
      date: DateTime.parse(json['date'] as String),
      startTime: json['startTime'] as String?,
      endTime: json['endTime'] as String?,
      coachId: json['coachId'] as String,
      coachName: json['coachName'] as String? ?? '',
      attendance: json['attendance'] as String? ?? 'PRESENT',
    );
  }
}

class MemberPackageDetail {
  final MemberPackage memberPackage;
  final List<MemberPackageSessionEntry> sessions;
  final List<MemberPackageAdjustment> adjustments;

  const MemberPackageDetail({
    required this.memberPackage,
    required this.sessions,
    required this.adjustments,
  });

  factory MemberPackageDetail.fromJson(Map<String, dynamic> json) {
    final pkg = json['memberPackage'] as Map<String, dynamic>;
    return MemberPackageDetail(
      memberPackage: MemberPackage(
        id: pkg['id'] as String,
        memberId: '',
        packageId: pkg['packageId'] as String,
        totalSessions: pkg['totalSessions'] as int,
        usedSessions: pkg['usedSessions'] as int,
        remainingSessions: pkg['remainingSessions'] as int,
        purchaseDate: DateTime.parse(pkg['purchaseDate'] as String),
        expiryDate: pkg['expiryDate'] != null
            ? DateTime.parse(pkg['expiryDate'] as String)
            : null,
        paidAmount: 0,
        paymentMethod: 'CASH',
        status: pkg['status'] as String? ?? 'ACTIVE',
        pauseStartDate: pkg['pauseStartDate'] != null
            ? DateTime.parse(pkg['pauseStartDate'] as String)
            : null,
        pauseEndDate: pkg['pauseEndDate'] != null
            ? DateTime.parse(pkg['pauseEndDate'] as String)
            : null,
        pauseExtensionDays: pkg['pauseExtensionDays'] as int? ?? 0,
        package: Package(
          id: pkg['packageId'] as String,
          organizationId: '',
          name: pkg['packageName'] as String? ?? '패키지',
          totalSessions: pkg['totalSessions'] as int,
          price: 0,
          isActive: true,
          isPublic: false,
          createdAt: DateTime.now(),
        ),
      ),
      sessions: ((json['sessions'] as List?) ?? const [])
          .map((e) =>
              MemberPackageSessionEntry.fromJson(e as Map<String, dynamic>))
          .toList(),
      adjustments: ((json['adjustments'] as List?) ?? const [])
          .map((e) =>
              MemberPackageAdjustment.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}
