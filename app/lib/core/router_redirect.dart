import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../providers/auth_provider.dart';
import '../providers/member_auth_provider.dart';
import 'api_client.dart';
import 'router_paths.dart';

String? handleRouterRedirect(Ref ref, GoRouterState state) {
  final adminStatus = ref.read(authProvider).status;
  final memberStatus = ref.read(memberAuthProvider).status;
  final currentPath = state.matchedLocation;

  if (adminStatus == AuthStatus.initial ||
      memberStatus == MemberAuthStatus.initial) {
    return currentPath == '/splash' ? null : '/splash';
  }

  final isMemberMode = ApiClient.isMemberMode;
  final adminAuth = adminStatus == AuthStatus.authenticated;
  final memberAuth = memberStatus == MemberAuthStatus.authenticated;

  if (adminAuth && memberAuth) {
    if (isMemberMode) {
      if (authPaths.contains(currentPath) || currentPath == '/splash') {
        return '/member/home';
      }
      return isMemberPath(currentPath) ? null : '/member/home';
    }

    final authState = ref.read(authProvider);
    final isSuperAdmin = authState.user?.isSuperAdmin ?? false;
    if (authState.hasNoCenters) {
      if (isSuperAdmin && isAdminPath(currentPath)) return null;
      if (centerPaths.contains(currentPath)) return null;
      return isSuperAdmin ? '/admin' : '/onboarding';
    }
    if (authState.needsCenterSelection) {
      if (isSuperAdmin && isAdminPath(currentPath)) return null;
      if (centerPaths.contains(currentPath)) return null;
      return '/centers';
    }
    if (authPaths.contains(currentPath) ||
        currentPath == '/splash' ||
        centerPaths.contains(currentPath)) {
      return '/home';
    }
    return isMemberPath(currentPath) ? '/home' : null;
  }

  if (adminAuth && !isMemberMode) {
    final authState = ref.read(authProvider);
    final isSuperAdmin = authState.user?.isSuperAdmin ?? false;

    if (authState.hasNoCenters) {
      if (isSuperAdmin && isAdminPath(currentPath)) return null;
      if (centerPaths.contains(currentPath)) return null;
      return isSuperAdmin ? '/admin' : '/onboarding';
    }

    if (authState.needsCenterSelection) {
      if (isSuperAdmin && isAdminPath(currentPath)) return null;
      if (centerPaths.contains(currentPath)) return null;
      return '/centers';
    }

    if (isSuperAdmin && isAdminPath(currentPath)) {
      return null;
    }

    if (authPaths.contains(currentPath) ||
        currentPath == '/splash' ||
        centerPaths.contains(currentPath)) {
      return '/home';
    }
    if (isMemberPath(currentPath)) {
      return '/home';
    }
    return null;
  }

  if (memberAuth && isMemberMode) {
    if (authPaths.contains(currentPath) || currentPath == '/splash') {
      return '/member/home';
    }
    return isMemberPath(currentPath) ? null : '/member/home';
  }

  if (currentPath == '/splash') return '/auth-select';
  if (authPaths.contains(currentPath)) return null;
  return '/auth-select';
}
