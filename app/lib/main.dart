import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'core/constants.dart';
import 'core/fcm_service.dart';
import 'core/router.dart';
import 'core/theme.dart';

final navigatorKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Hive.initFlutter();
  await Hive.openBox(AppConstants.authBox);
  await initializeDateFormatting('ko_KR', null);

  try {
    await FcmService.initialize();
  } catch (e) {
    debugPrint('Firebase init failed (expected without config): $e');
  }

  FcmService.navigatorKey = navigatorKey;

  runApp(const ProviderScope(child: CoachDeskApp()));
}

class CoachDeskApp extends ConsumerWidget {
  const CoachDeskApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);

    return MaterialApp.router(
      title: 'CoachDesk',
      theme: AppTheme.lightTheme,
      routerConfig: router,
      debugShowCheckedModeBanner: false,
    );
  }
}
