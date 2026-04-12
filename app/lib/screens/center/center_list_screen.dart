import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import '../../providers/auth_provider.dart';
import '../../models/organization.dart';

class CenterListScreen extends ConsumerStatefulWidget {
  const CenterListScreen({super.key});

  @override
  ConsumerState<CenterListScreen> createState() => _CenterListScreenState();
}

class _CenterListScreenState extends ConsumerState<CenterListScreen> {
  bool _isSelecting = false;

  @override
  void initState() {
    super.initState();
    Future.microtask(() => ref.read(authProvider.notifier).fetchCenters());
  }

  String _roleLabel(String? role) {
    switch (role) {
      case 'OWNER':
        return '메인관리자';
      case 'MANAGER':
        return '운영관리자';
      case 'STAFF':
        return '스태프';
      case 'VIEWER':
        return '뷰어';
      default:
        return '';
    }
  }

  Color _roleColor(String? role) {
    switch (role) {
      case 'OWNER':
        return AppTheme.primaryColor;
      case 'MANAGER':
        return AppTheme.secondaryColor;
      case 'STAFF':
        return Colors.teal;
      case 'VIEWER':
        return Colors.grey;
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authProvider);
    final centers = authState.centers;

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: AppTheme.splashGradient,
        ),
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
                child: Column(
                  children: [
                    const Text(
                      '내 센터',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '관리할 센터를 선택하세요',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.white.withValues(alpha: 0.85),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Container(
                  margin: const EdgeInsets.only(top: 16),
                  decoration: const BoxDecoration(
                    color: AppTheme.backgroundColor,
                    borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(24),
                      topRight: Radius.circular(24),
                    ),
                  ),
                  child: Column(
                    children: [
                      Expanded(
                        child: authState.isLoading
                            ? const Center(child: CircularProgressIndicator())
                            : authState.error != null
                                ? Center(
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(Icons.error_outline,
                                            size: 48,
                                            color: Colors.grey.shade400),
                                        const SizedBox(height: 12),
                                        Text(authState.error!,
                                            style: TextStyle(
                                                color: Colors.grey.shade500)),
                                        const SizedBox(height: 12),
                                        TextButton(
                                          onPressed: () => ref
                                              .read(authProvider.notifier)
                                              .fetchCenters(),
                                          child: const Text('다시 시도'),
                                        ),
                                      ],
                                    ),
                                  )
                                : centers.isEmpty
                                    ? _buildEmptyState()
                                    : ListView.builder(
                                        padding: const EdgeInsets.all(20),
                                        itemCount: centers.length,
                                        itemBuilder: (context, index) =>
                                            _buildCenterCard(centers[index]),
                                      ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                        child: SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: () => context.go('/onboarding'),
                            icon: const Icon(Icons.add),
                            label: const Text('센터 추가'),
                            style: OutlinedButton.styleFrom(
                              padding:
                                  const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12)),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.business_outlined,
              size: 64, color: Colors.grey.shade300),
          const SizedBox(height: 16),
          Text(
            '소속된 센터가 없습니다',
            style: TextStyle(
              fontSize: 16,
              color: Colors.grey.shade500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCenterCard(Organization center) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: GestureDetector(
        onTap: _isSelecting
            ? null
            : () async {
                setState(() => _isSelecting = true);
                try {
                  await ref
                      .read(authProvider.notifier)
                      .selectCenter(center.id);
                  // Router redirect navigates to /home when selectedCenter is set
                } finally {
                  if (mounted) setState(() => _isSelecting = false);
                }
              },
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: _roleColor(center.role).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.business_rounded,
                  color: _roleColor(center.role),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      center.name,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color:
                                _roleColor(center.role).withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            _roleLabel(center.role),
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: _roleColor(center.role),
                            ),
                          ),
                        ),
                        if (center.memberCount != null) ...[
                          const SizedBox(width: 8),
                          Text(
                            '회원 ${center.memberCount}명',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade500,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: Colors.grey.shade400),
            ],
          ),
        ),
      ),
    );
  }
}
