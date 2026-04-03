class Package {
  final String id;
  final String organizationId;
  final String name;
  final int totalSessions;
  final int price;
  final int? validDays;
  final bool isActive;
  final DateTime createdAt;

  const Package({
    required this.id,
    required this.organizationId,
    required this.name,
    required this.totalSessions,
    required this.price,
    this.validDays,
    required this.isActive,
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
      createdAt: DateTime.parse(json['createdAt'] as String),
    );
  }

  Map<String, dynamic> toJson() => {
    'name': name,
    'totalSessions': totalSessions,
    'price': price,
    'validDays': validDays,
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
    this.package,
  });

  factory MemberPackage.fromJson(Map<String, dynamic> json) {
    return MemberPackage(
      id: json['id'] as String,
      memberId: json['memberId'] as String,
      packageId: json['packageId'] as String,
      totalSessions: json['totalSessions'] as int,
      usedSessions: json['usedSessions'] as int,
      remainingSessions: json['remainingSessions'] as int,
      purchaseDate: DateTime.parse(json['purchaseDate'] as String),
      expiryDate: json['expiryDate'] != null ? DateTime.parse(json['expiryDate'] as String) : null,
      paidAmount: json['paidAmount'] as int,
      paymentMethod: json['paymentMethod'] as String? ?? 'CASH',
      status: json['status'] as String? ?? 'ACTIVE',
      package: json['package'] != null ? Package.fromJson(json['package'] as Map<String, dynamic>) : null,
    );
  }
}
