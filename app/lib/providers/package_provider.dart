import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/api_client.dart';
import '../models/package.dart';

class PackageState {
  final List<Package> packages;
  final bool isLoading;
  final String? error;

  const PackageState({this.packages = const [], this.isLoading = false, this.error});

  PackageState copyWith({List<Package>? packages, bool? isLoading, String? error}) {
    return PackageState(
      packages: packages ?? this.packages,
      isLoading: isLoading ?? this.isLoading,
      error: error,
    );
  }
}

class PackageNotifier extends Notifier<PackageState> {
  @override
  PackageState build() => const PackageState();

  Dio get _dio => ref.read(dioProvider);

  Future<void> fetchPackages() async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final response = await _dio.get('/packages');
      final packages = (response.data as List)
          .map((json) => Package.fromJson(json as Map<String, dynamic>))
          .toList();
      state = state.copyWith(packages: packages, isLoading: false);
    } on DioException catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: e.response?.data?['error'] as String? ?? 'Failed to load packages',
      );
    }
  }

  Future<bool> createPackage(Map<String, dynamic> data) async {
    try {
      await _dio.post('/packages', data: data);
      await fetchPackages();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> updatePackage(String id, Map<String, dynamic> data) async {
    try {
      await _dio.put('/packages/$id', data: data);
      await fetchPackages();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> assignToMember({
    required String memberId,
    required String packageId,
    required int paidAmount,
    String paymentMethod = 'CASH',
  }) async {
    try {
      await _dio.post('/packages/assign', data: {
        'memberId': memberId,
        'packageId': packageId,
        'paidAmount': paidAmount,
        'paymentMethod': paymentMethod,
      });
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<List<MemberPackage>> getMemberPackages(String memberId) async {
    try {
      final response = await _dio.get('/packages/member/$memberId');
      return (response.data as List)
          .map((json) => MemberPackage.fromJson(json as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<({bool success, String? errorMessage})> adjustMemberPackage({
    required String memberPackageId,
    required String type,
    int? sessionDelta,
    String? newExpiryDate,
    String? reason,
  }) async {
    try {
      await _dio.patch(
        '/packages/member-packages/$memberPackageId/adjust',
        data: {
          'type': type,
          if (sessionDelta != null) 'sessionDelta': sessionDelta,
          if (newExpiryDate != null) 'newExpiryDate': newExpiryDate,
          if (reason != null && reason.isNotEmpty) 'reason': reason,
        },
      );
      return (success: true, errorMessage: null);
    } on DioException catch (e) {
      return (
        success: false,
        errorMessage: e.response?.data?['error'] as String? ?? '조정에 실패했습니다',
      );
    }
  }
}

final packageProvider = NotifierProvider<PackageNotifier, PackageState>(PackageNotifier.new);
