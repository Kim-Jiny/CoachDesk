import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../core/constants.dart';

class UiSettingsNotifier extends Notifier<bool> {
  @override
  bool build() {
    final box = Hive.box(AppConstants.authBox);
    return box.get(AppConstants.hideRevenueAmountKey) as bool? ?? false;
  }

  Future<void> setHideRevenueAmount(bool value) async {
    final box = Hive.box(AppConstants.authBox);
    await box.put(AppConstants.hideRevenueAmountKey, value);
    state = value;
  }

  Future<void> toggleHideRevenueAmount() async {
    await setHideRevenueAmount(!state);
  }
}

final hideRevenueAmountProvider = NotifierProvider<UiSettingsNotifier, bool>(
  UiSettingsNotifier.new,
);
