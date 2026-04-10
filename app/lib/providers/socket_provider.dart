import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/socket_service.dart';
import 'auth_provider.dart';
import 'member_auth_provider.dart';

/// Watches auth state and manages socket connection lifecycle.
/// Watch this provider in MainShell to keep the connection alive.
final socketConnectionProvider = Provider<void>((ref) {
  final adminStatus = ref.watch(authProvider).status;
  final memberStatus = ref.watch(memberAuthProvider).status;

  final isAuthenticated = adminStatus == AuthStatus.authenticated ||
      memberStatus == MemberAuthStatus.authenticated;

  if (isAuthenticated) {
    SocketService.instance.connect();
  } else {
    SocketService.instance.disconnect();
  }

  ref.onDispose(() {
    SocketService.instance.disconnect();
  });
});
