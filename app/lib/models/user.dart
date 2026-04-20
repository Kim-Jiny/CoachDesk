class User {
  final String id;
  final String email;
  final String name;
  final String? phone;
  final String? profileImage;
  final String bookingMode;
  final String reservationPolicy;
  final String? reservationNoticeText;
  final String? reservationNoticeImageUrl;
  final int reservationOpenDaysBefore;
  final int reservationOpenHoursBefore;
  final int reservationCancelDeadlineMinutes;

  const User({
    required this.id,
    required this.email,
    required this.name,
    this.phone,
    this.profileImage,
    this.bookingMode = 'PRIVATE',
    this.reservationPolicy = 'AUTO_CONFIRM',
    this.reservationNoticeText,
    this.reservationNoticeImageUrl,
    this.reservationOpenDaysBefore = 30,
    this.reservationOpenHoursBefore = 0,
    this.reservationCancelDeadlineMinutes = 120,
  });

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id'] as String,
      email: json['email'] as String,
      name: json['name'] as String,
      phone: json['phone'] as String?,
      profileImage: json['profileImage'] as String?,
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
    'email': email,
    'name': name,
    'phone': phone,
    'profileImage': profileImage,
    'bookingMode': bookingMode,
    'reservationPolicy': reservationPolicy,
    'reservationNoticeText': reservationNoticeText,
    'reservationNoticeImageUrl': reservationNoticeImageUrl,
    'reservationOpenDaysBefore': reservationOpenDaysBefore,
    'reservationOpenHoursBefore': reservationOpenHoursBefore,
    'reservationCancelDeadlineMinutes': reservationCancelDeadlineMinutes,
  };

  User copyWith({
    String? id,
    String? email,
    String? name,
    String? phone,
    String? profileImage,
    String? bookingMode,
    String? reservationPolicy,
    String? reservationNoticeText,
    String? reservationNoticeImageUrl,
    int? reservationOpenDaysBefore,
    int? reservationOpenHoursBefore,
    int? reservationCancelDeadlineMinutes,
  }) {
    return User(
      id: id ?? this.id,
      email: email ?? this.email,
      name: name ?? this.name,
      phone: phone ?? this.phone,
      profileImage: profileImage ?? this.profileImage,
      bookingMode: bookingMode ?? this.bookingMode,
      reservationPolicy: reservationPolicy ?? this.reservationPolicy,
      reservationNoticeText:
          reservationNoticeText ?? this.reservationNoticeText,
      reservationNoticeImageUrl:
          reservationNoticeImageUrl ?? this.reservationNoticeImageUrl,
      reservationOpenDaysBefore:
          reservationOpenDaysBefore ?? this.reservationOpenDaysBefore,
      reservationOpenHoursBefore:
          reservationOpenHoursBefore ?? this.reservationOpenHoursBefore,
      reservationCancelDeadlineMinutes:
          reservationCancelDeadlineMinutes ??
          this.reservationCancelDeadlineMinutes,
    );
  }
}
