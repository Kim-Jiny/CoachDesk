import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../providers/auth_provider.dart';
import '../providers/member_auth_provider.dart';
import 'api_client.dart';
import '../screens/splash_screen.dart';
import '../screens/auth/login_screen.dart';
import '../screens/auth/register_screen.dart';
import '../screens/auth/auth_select_screen.dart';
import '../screens/auth/member_login_screen.dart';
import '../screens/auth/member_register_screen.dart';
import '../screens/member_home/member_home_screen.dart';
import '../screens/member_home/member_class_detail_screen.dart';
import '../screens/main_shell.dart';
import '../screens/home/home_screen.dart';
import '../screens/schedule/schedule_screen.dart';
import '../screens/members/member_list_screen.dart';
import '../screens/members/member_detail_screen.dart';
import '../screens/members/member_form_screen.dart';
import '../screens/settings/settings_screen.dart';
import '../screens/reservation/reservation_form_screen.dart';
import '../screens/packages/package_list_screen.dart';
import '../screens/packages/package_form_screen.dart';
import '../screens/packages/assign_package_screen.dart';
import '../screens/session/session_complete_screen.dart';
import '../screens/session/session_list_screen.dart';
import '../screens/notifications/notification_screen.dart';
import '../screens/report/revenue_report_screen.dart';
import '../screens/report/attendance_report_screen.dart';
import '../screens/settings/schedule_setting_screen.dart';
import '../screens/settings/team_management_screen.dart';
import '../models/package.dart';
import '../models/reservation.dart';

final rootNavigatorKey = GlobalKey<NavigatorState>();

final shellBranchKeys = <int, GlobalKey<NavigatorState>>{
  0: GlobalKey<NavigatorState>(debugLabel: 'home'),
  1: GlobalKey<NavigatorState>(debugLabel: 'schedule'),
  2: GlobalKey<NavigatorState>(debugLabel: 'members'),
  3: GlobalKey<NavigatorState>(debugLabel: 'more'),
};

const _authPaths = {'/login', '/register', '/auth-select', '/member/login', '/member/register'};

bool _isMemberPath(String path) => path == '/member/home' || path.startsWith('/member/');

final routerProvider = Provider<GoRouter>((ref) {
  final authNotifier = _AuthChangeNotifier(ref);
  ref.onDispose(() => authNotifier.dispose());

  return GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: '/splash',
    debugLogDiagnostics: false,
    refreshListenable: authNotifier,
    redirect: (context, state) {
      final adminStatus = ref.read(authProvider).status;
      final memberStatus = ref.read(memberAuthProvider).status;
      final currentPath = state.matchedLocation;

      // Still initializing
      if (adminStatus == AuthStatus.initial && memberStatus == MemberAuthStatus.initial) {
        return currentPath == '/splash' ? null : '/splash';
      }

      final isMemberMode = ApiClient.isMemberMode;
      final adminAuth = adminStatus == AuthStatus.authenticated;
      final memberAuth = memberStatus == MemberAuthStatus.authenticated;

      // Both authenticated — use isMemberMode flag to decide
      if (adminAuth && memberAuth) {
        if (_authPaths.contains(currentPath) || currentPath == '/splash') {
          return isMemberMode ? '/member/home' : '/home';
        }
        if (isMemberMode) {
          return _isMemberPath(currentPath) ? null : '/member/home';
        }
        return _isMemberPath(currentPath) ? '/home' : null;
      }

      // Admin authenticated (not in member mode)
      if (adminAuth && !isMemberMode) {
        if (_authPaths.contains(currentPath) || currentPath == '/splash') return '/home';
        if (_isMemberPath(currentPath)) return '/home';
        return null;
      }

      // Member authenticated (in member mode)
      if (memberAuth && isMemberMode) {
        if (_authPaths.contains(currentPath) || currentPath == '/splash') return '/member/home';
        return _isMemberPath(currentPath) ? null : '/member/home';
      }

      // Unauthenticated — splash redirects to auth-select
      if (currentPath == '/splash') return '/auth-select';

      // Allow auth paths
      if (_authPaths.contains(currentPath)) return null;

      return '/auth-select';
    },
    routes: [
      GoRoute(
        path: '/splash',
        builder: (context, state) => const SplashScreen(),
      ),
      GoRoute(
        path: '/auth-select',
        builder: (context, state) => const AuthSelectScreen(),
      ),
      GoRoute(
        path: '/login',
        builder: (context, state) => const LoginScreen(),
      ),
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
      // Full-screen routes
      GoRoute(
        path: '/members/:id',
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) => MemberDetailScreen(
          memberId: state.pathParameters['id']!,
        ),
      ),
      GoRoute(
        path: '/members-form',
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) => MemberFormScreen(
          member: state.extra as Map<String, dynamic>?,
        ),
      ),
      GoRoute(
        path: '/reservations/new',
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) => ReservationFormScreen(
          initialData: state.extra as Map<String, dynamic>?,
        ),
      ),
      GoRoute(
        path: '/reservations/complete',
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) => SessionCompleteScreen(
          reservation: state.extra as Reservation,
        ),
      ),
      // Package routes
      GoRoute(
        path: '/packages',
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) => const PackageListScreen(),
      ),
      GoRoute(
        path: '/packages/form',
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) => PackageFormScreen(
          package: state.extra as Package?,
        ),
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
      // Session routes
      GoRoute(
        path: '/sessions',
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) => SessionListScreen(
          memberId: state.extra as String?,
        ),
      ),
      GoRoute(
        path: '/notifications',
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) => const NotificationScreen(),
      ),
      // Report routes
      GoRoute(
        path: '/reports/revenue',
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) => const RevenueReportScreen(),
      ),
      GoRoute(
        path: '/reports/attendance',
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) => const AttendanceReportScreen(),
      ),
      // Settings sub-routes
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
      // Main Shell with bottom navigation
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
                path: '/settings',
                builder: (context, state) => const SettingsScreen(),
              ),
            ],
          ),
        ],
      ),
    ],
  );
});

class _AuthChangeNotifier extends ChangeNotifier {
  late final ProviderSubscription<AuthState> _adminSub;
  late final ProviderSubscription<MemberAuthState> _memberSub;

  _AuthChangeNotifier(Ref ref) {
    _adminSub = ref.listen(authProvider, (_, _) {
      notifyListeners();
    });
    _memberSub = ref.listen(memberAuthProvider, (_, _) {
      notifyListeners();
    });
  }

  @override
  void dispose() {
    _adminSub.close();
    _memberSub.close();
    super.dispose();
  }
}
