import 'package:flutter/widgets.dart';
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

  final lifecycleListener = AppLifecycleListener(
    onResume: () {
      final admin = ref.read(authProvider).status;
      final member = ref.read(memberAuthProvider).status;
      final stillAuthenticated = admin == AuthStatus.authenticated ||
          member == MemberAuthStatus.authenticated;
      if (stillAuthenticated) {
        SocketService.instance.connect();
      }
    },
  );

  ref.onDispose(() {
    lifecycleListener.dispose();
    SocketService.instance.disconnect();
  });
});
