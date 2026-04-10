class Package {
  final String id;
  final String organizationId;
  final String name;
  final int totalSessions;
  final int price;
  final int? validDays;
  final bool isActive;
  final bool isPublic;
  final DateTime createdAt;

  const Package({
    required this.id,
    required this.organizationId,
    required this.name,
    required this.totalSessions,
    required this.price,
    this.validDays,
    required this.isActive,
    required this.isPublic,
    required this.createdAt,
  });

  factory Package.fromJson(Map<String, dynamic> json) {
    return Package(
      id: json['id'] as String,
      organizationId: json['organizationId'] as String,
      name: json['name'] as String,
      totalSessions: json['totalSessions'] as int,
      price: json['price'] as int,
      validDays: json['validDays'] as int?,
      isActive: json['isActive'] as bool? ?? true,
      isPublic: json['isPublic'] as bool? ?? false,
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
  };
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
