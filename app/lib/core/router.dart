import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../providers/auth_provider.dart';
import '../providers/member_auth_provider.dart';
import 'router_redirect.dart';
import 'router_routes.dart';

final rootNavigatorKey = GlobalKey<NavigatorState>();

final shellBranchKeys = <int, GlobalKey<NavigatorState>>{
  0: GlobalKey<NavigatorState>(debugLabel: 'home'),
  1: GlobalKey<NavigatorState>(debugLabel: 'schedule'),
  2: GlobalKey<NavigatorState>(debugLabel: 'members'),
  3: GlobalKey<NavigatorState>(debugLabel: 'chat'),
  4: GlobalKey<NavigatorState>(debugLabel: 'more'),
};

final routerProvider = Provider<GoRouter>((ref) {
  final authNotifier = _AuthChangeNotifier(ref);
  ref.onDispose(() => authNotifier.dispose());

  return GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: '/splash',
    debugLogDiagnostics: false,
    refreshListenable: authNotifier,
    redirect: (context, state) => handleRouterRedirect(ref, state),
    routes: buildAppRoutes(
      rootNavigatorKey: rootNavigatorKey,
      shellBranchKeys: shellBranchKeys,
    ),
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
