import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../models/package.dart';
import '../models/reservation.dart';
import '../screens/auth/auth_select_screen.dart';
import '../screens/auth/login_screen.dart';
import '../screens/auth/member_login_screen.dart';
import '../screens/auth/member_register_screen.dart';
import '../screens/auth/register_screen.dart';
import '../screens/center/center_create_screen.dart';
import '../screens/center/center_join_screen.dart';
import '../screens/center/center_list_screen.dart';
import '../screens/center/center_onboarding_screen.dart';
import '../screens/chat/chat_room_list_screen.dart';
import '../screens/chat/chat_screen.dart';
import '../screens/home/home_screen.dart';
import '../screens/main_shell.dart';
import '../screens/member_home/member_class_detail_screen.dart';
import '../screens/member_home/member_home_screen.dart';
import '../screens/member_home/member_reservation_history_screen.dart';
import '../screens/members/member_detail_screen.dart';
import '../screens/members/member_form_screen.dart';
import '../screens/members/member_list_screen.dart';
import '../screens/notifications/member_notification_screen.dart';
import '../screens/notifications/notification_screen.dart';
import '../screens/packages/assign_package_screen.dart';
import '../screens/packages/package_form_screen.dart';
import '../screens/packages/package_list_screen.dart';
import '../screens/report/attendance_report_screen.dart';
import '../screens/report/revenue_report_screen.dart';
import '../screens/reservation/pending_reservations_screen.dart';
import '../screens/reservation/reservation_form_screen.dart';
import '../screens/schedule/schedule_screen.dart';
import '../screens/session/session_complete_screen.dart';
import '../screens/session/session_list_screen.dart';
import '../screens/settings/center_settings_screen.dart';
import '../screens/settings/notification_settings_screen.dart';
import '../screens/settings/profile_edit_screen.dart';
import '../screens/settings/schedule_setting_screen.dart';
import '../screens/settings/settings_screen.dart';
import '../screens/settings/team_management_screen.dart';
import '../screens/splash_screen.dart';

List<RouteBase> buildAppRoutes({
  required GlobalKey<NavigatorState> rootNavigatorKey,
  required Map<int, GlobalKey<NavigatorState>> shellBranchKeys,
}) {
  return [
    GoRoute(
      path: '/splash',
      builder: (context, state) => const SplashScreen(),
    ),
    GoRoute(
      path: '/auth-select',
      builder: (context, state) => const AuthSelectScreen(),
    ),
    GoRoute(path: '/login', builder: (context, state) => const LoginScreen()),
    GoRoute(
      path: '/register',
      builder: (context, state) => const RegisterScreen(),
    ),
    GoRoute(
      path: '/member/login',
      builder: (context, state) => const MemberLoginScreen(),
    ),
    GoRoute(
      path: '/member/register',
      builder: (context, state) => const MemberRegisterScreen(),
    ),
    GoRoute(
      path: '/onboarding',
      builder: (context, state) => const CenterOnboardingScreen(),
    ),
    GoRoute(
      path: '/centers',
      builder: (context, state) => const CenterListScreen(),
    ),
    GoRoute(
      path: '/centers/create',
      builder: (context, state) => const CenterCreateScreen(),
    ),
    GoRoute(
      path: '/centers/join',
      builder: (context, state) => const CenterJoinScreen(),
    ),
    GoRoute(
      path: '/member/home',
      builder: (context, state) => const MemberHomeScreen(),
    ),
    GoRoute(
      path: '/member/class/:orgId',
      parentNavigatorKey: rootNavigatorKey,
      builder: (context, state) => MemberClassDetailScreen(
        orgId: state.pathParameters['orgId']!,
        organizationName: state.extra as String? ?? '',
      ),
    ),
    GoRoute(
      path: '/member/history',
      parentNavigatorKey: rootNavigatorKey,
      builder: (context, state) => const MemberReservationHistoryScreen(),
    ),
    GoRoute(
      path: '/member/notifications',
      parentNavigatorKey: rootNavigatorKey,
      builder: (context, state) => const MemberNotificationScreen(),
    ),
    GoRoute(
      path: '/members/:id',
      parentNavigatorKey: rootNavigatorKey,
      builder: (context, state) =>
          MemberDetailScreen(memberId: state.pathParameters['id']!),
    ),
    GoRoute(
      path: '/members-form',
      parentNavigatorKey: rootNavigatorKey,
      builder: (context, state) =>
          MemberFormScreen(member: state.extra as Map<String, dynamic>?),
    ),
    GoRoute(
      path: '/reservations/new',
      parentNavigatorKey: rootNavigatorKey,
      builder: (context, state) => ReservationFormScreen(
        initialData: state.extra as Map<String, dynamic>?,
      ),
    ),
    GoRoute(
      path: '/reservations/pending',
      parentNavigatorKey: rootNavigatorKey,
      builder: (context, state) => const PendingReservationsScreen(),
    ),
    GoRoute(
      path: '/reservations/complete',
      parentNavigatorKey: rootNavigatorKey,
      builder: (context, state) =>
          SessionCompleteScreen(reservation: state.extra as Reservation),
    ),
    GoRoute(
      path: '/packages',
      parentNavigatorKey: rootNavigatorKey,
      builder: (context, state) => PackageListScreen(
        initialScope: state.uri.queryParameters['scope'] == 'admin'
            ? 'ADMIN'
            : 'CENTER',
      ),
    ),
    GoRoute(
      path: '/packages/form',
      parentNavigatorKey: rootNavigatorKey,
      builder: (context, state) {
        final extra = state.extra;
        if (extra is PackageFormArgs) {
          return PackageFormScreen(
            package: extra.package,
            initialScope: extra.initialScope,
          );
        }
        return PackageFormScreen(package: extra as Package?);
      },
    ),
    GoRoute(
      path: '/packages/assign',
      parentNavigatorKey: rootNavigatorKey,
      builder: (context, state) {
        final data = state.extra as Map<String, String>;
        return AssignPackageScreen(
          memberId: data['memberId']!,
          memberName: data['memberName']!,
        );
      },
    ),
    GoRoute(
      path: '/sessions',
      parentNavigatorKey: rootNavigatorKey,
      builder: (context, state) =>
          SessionListScreen(memberId: state.extra as String?),
    ),
    GoRoute(
      path: '/notifications',
      parentNavigatorKey: rootNavigatorKey,
      builder: (context, state) => const NotificationScreen(),
    ),
    GoRoute(
      path: '/reports/revenue',
      parentNavigatorKey: rootNavigatorKey,
      builder: (context, state) => RevenueReportScreen(
        initialMonth: state.extra as DateTime?,
        reportScope: state.uri.queryParameters['scope'] == 'admin'
            ? 'admin'
            : 'center',
      ),
    ),
    GoRoute(
      path: '/reports/attendance',
      parentNavigatorKey: rootNavigatorKey,
      builder: (context, state) => AttendanceReportScreen(
        reportScope: state.uri.queryParameters['scope'] == 'admin'
            ? 'admin'
            : 'center',
      ),
    ),
    GoRoute(
      path: '/settings/center',
      parentNavigatorKey: rootNavigatorKey,
      builder: (context, state) => const CenterSettingsScreen(),
    ),
    GoRoute(
      path: '/settings/profile',
      parentNavigatorKey: rootNavigatorKey,
      builder: (context, state) => const ProfileEditScreen(),
    ),
    GoRoute(
      path: '/settings/schedules',
      parentNavigatorKey: rootNavigatorKey,
      builder: (context, state) => const ScheduleSettingScreen(),
    ),
    GoRoute(
      path: '/settings/team',
      parentNavigatorKey: rootNavigatorKey,
      builder: (context, state) => const TeamManagementScreen(),
    ),
    GoRoute(
      path: '/settings/notifications',
      parentNavigatorKey: rootNavigatorKey,
      builder: (context, state) =>
          const NotificationSettingsScreen(isMember: false),
    ),
    GoRoute(
      path: '/member/settings/notifications',
      parentNavigatorKey: rootNavigatorKey,
      builder: (context, state) =>
          const NotificationSettingsScreen(isMember: true),
    ),
    GoRoute(
      path: '/member/settings',
      parentNavigatorKey: rootNavigatorKey,
      builder: (context, state) => const SettingsScreen(isMember: true),
    ),
    GoRoute(
      path: '/chat/:roomId',
      parentNavigatorKey: rootNavigatorKey,
      builder: (context, state) =>
          ChatScreen(roomId: state.pathParameters['roomId']!),
    ),
    GoRoute(
      path: '/member/chat',
      parentNavigatorKey: rootNavigatorKey,
      builder: (context, state) => const ChatRoomListScreen(),
    ),
    GoRoute(
      path: '/member/chat/:roomId',
      parentNavigatorKey: rootNavigatorKey,
      builder: (context, state) =>
          ChatScreen(roomId: state.pathParameters['roomId']!),
    ),
    StatefulShellRoute.indexedStack(
      builder: (context, state, navigationShell) {
        return MainShell(navigationShell: navigationShell);
      },
      branches: [
        StatefulShellBranch(
          navigatorKey: shellBranchKeys[0]!,
          routes: [
            GoRoute(
              path: '/home',
              builder: (context, state) => const HomeScreen(),
            ),
          ],
        ),
        StatefulShellBranch(
          navigatorKey: shellBranchKeys[1]!,
          routes: [
            GoRoute(
              path: '/schedule',
              builder: (context, state) => const ScheduleScreen(),
            ),
          ],
        ),
        StatefulShellBranch(
          navigatorKey: shellBranchKeys[2]!,
          routes: [
            GoRoute(
              path: '/members',
              builder: (context, state) => const MemberListScreen(),
            ),
          ],
        ),
        StatefulShellBranch(
          navigatorKey: shellBranchKeys[3]!,
          routes: [
            GoRoute(
              path: '/chat',
              builder: (context, state) => const ChatRoomListScreen(),
            ),
          ],
        ),
        StatefulShellBranch(
          navigatorKey: shellBranchKeys[4]!,
          routes: [
            GoRoute(
              path: '/settings',
              builder: (context, state) => const SettingsScreen(),
            ),
          ],
        ),
      ],
    ),
  ];
}
