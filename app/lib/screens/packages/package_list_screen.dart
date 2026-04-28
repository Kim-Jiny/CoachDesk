import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/theme.dart';
import '../../providers/package_provider.dart';
import '../../widgets/common.dart';
import 'package_form_screen.dart';

class PackageListScreen extends ConsumerStatefulWidget {
  final String initialScope;

  const PackageListScreen({super.key, this.initialScope = 'CENTER'});

  @override
  ConsumerState<PackageListScreen> createState() => _PackageListScreenState();
}

class _PackageListScreenState extends ConsumerState<PackageListScreen> {
  final _searchController = TextEditingController();
  String _statusFilter = 'all';
  late String _scopeFilter;

  @override
  void initState() {
    super.initState();
    _scopeFilter = widget.initialScope;
    Future.microtask(() => ref.read(packageProvider.notifier).fetchPackages());
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pkgState = ref.watch(packageProvider);
    final formatter = NumberFormat('#,###');
    final filteredPackages = pkgState.packages.where((pkg) {
      final matchesScope = pkg.scope == _scopeFilter;
      final matchesStatus = switch (_statusFilter) {
        'active' => pkg.isActive,
        'inactive' => !pkg.isActive,
        _ => true,
      };
      final query = _searchController.text.trim().toLowerCase();
      final matchesQuery = query.isEmpty
          ? true
          : pkg.name.toLowerCase().contains(query);
      return matchesScope && matchesStatus && matchesQuery;
    }).toList();
    final scopeLabel = _scopeFilter == 'ADMIN' ? '관리자 패키지' : '센터 패키지';

    return Scaffold(
      appBar: AppBar(title: Text(scopeLabel)),
      body: pkgState.isLoading
          ? const ShimmerLoading(style: ShimmerStyle.card, itemCount: 5)
          : pkgState.packages.isEmpty
          ? EmptyState(
              icon: Icons.inventory_2_outlined,
              message: '등록된 패키지가 없습니다',
              actionLabel: '패키지 등록',
              onAction: _openCreateForm,
            )
          : RefreshIndicator(
              onRefresh: () =>
                  ref.read(packageProvider.notifier).fetchPackages(),
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: AppTheme.softShadow,
                    ),
                    child: TextField(
                      controller: _searchController,
                      onChanged: (_) => setState(() {}),
                      decoration: InputDecoration(
                        hintText: '패키지명 검색',
                        prefixIcon: Icon(
                          Icons.search_rounded,
                          color: Colors.grey.shade400,
                        ),
                        suffixIcon: _searchController.text.isNotEmpty
                            ? IconButton(
                                onPressed: () {
                                  _searchController.clear();
                                  setState(() {});
                                },
                                icon: Icon(
                                  Icons.clear_rounded,
                                  color: Colors.grey.shade400,
                                ),
                              )
                            : null,
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 14,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        _FilterChip(
                          label: '센터 패키지',
                          selected: _scopeFilter == 'CENTER',
                          onTap: () => setState(() => _scopeFilter = 'CENTER'),
                        ),
                        const SizedBox(width: 8),
                        _FilterChip(
                          label: '관리자 패키지',
                          selected: _scopeFilter == 'ADMIN',
                          onTap: () => setState(() => _scopeFilter = 'ADMIN'),
                        ),
                        const SizedBox(width: 12),
                        _FilterChip(
                          label: '전체',
                          selected: _statusFilter == 'all',
                          onTap: () => setState(() => _statusFilter = 'all'),
                        ),
                        const SizedBox(width: 8),
                        _FilterChip(
                          label: '활성',
                          selected: _statusFilter == 'active',
                          onTap: () => setState(() => _statusFilter = 'active'),
                        ),
                        const SizedBox(width: 8),
                        _FilterChip(
                          label: '비활성',
                          selected: _statusFilter == 'inactive',
                          onTap: () =>
                              setState(() => _statusFilter = 'inactive'),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '총 ${filteredPackages.length}개',
                    style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                  ),
                  const SizedBox(height: 12),
                  if (filteredPackages.isEmpty)
                    EmptyState(
                      icon: Icons.search_off_rounded,
                      message: '조건에 맞는 $scopeLabel가 없습니다',
                      actionLabel: '새 $scopeLabel 등록',
                      onAction: () {
                        if (_searchController.text.isNotEmpty ||
                            _statusFilter != 'all') {
                          _searchController.clear();
                          setState(() => _statusFilter = 'all');
                          return;
                        }
                        _openCreateForm();
                      },
                    )
                  else
                    ...filteredPackages.map((pkg) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: GestureDetector(
                          onTap: () => context.push(
                            '/packages/form',
                            extra: PackageFormArgs(package: pkg),
                          ),
                          child: Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(16),
                              boxShadow: AppTheme.softShadow,
                            ),
                            child: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color: pkg.isActive
                                        ? AppTheme.primaryColor.withValues(
                                            alpha: 0.1,
                                          )
                                        : Colors.grey.shade100,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Icon(
                                    Icons.inventory_2_rounded,
                                    color: pkg.isActive
                                        ? AppTheme.primaryColor
                                        : Colors.grey,
                                    size: 22,
                                  ),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        pkg.name,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w600,
                                          fontSize: 15,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        '${pkg.scopeLabel}  ·  ${pkg.totalSessions}회  ·  ${formatter.format(pkg.price)}원'
                                        '${pkg.validDays != null ? '  ·  ${pkg.validDays}일' : ''}',
                                        style: TextStyle(
                                          fontSize: 13,
                                          color: Colors.grey.shade500,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        '사용 중 ${pkg.activeMemberCount}명 · 누적 사용 ${pkg.totalUsedSessions}회',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.grey.shade600,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                      Wrap(
                                        spacing: 6,
                                        runSpacing: 6,
                                        children: [
                                          StatusBadge(
                                            label: pkg.scopeLabel,
                                            color: pkg.isAdminScoped
                                                ? Colors.deepOrange
                                                : Colors.teal,
                                          ),
                                          StatusBadge(
                                            label: pkg.isActive ? '활성' : '비활성',
                                            color: pkg.isActive
                                                ? AppTheme.successColor
                                                : Colors.grey,
                                          ),
                                          StatusBadge(
                                            label: pkg.isPublic ? '공개' : '비공개',
                                            color: pkg.isPublic
                                                ? AppTheme.primaryColor
                                                : Colors.blueGrey,
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Icon(
                                  Icons.chevron_right,
                                  color: Colors.grey.shade400,
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    }),
                ],
              ),
            ),
      floatingActionButton: FloatingActionButton(
        heroTag: 'package_list_add_fab',
        onPressed: _openCreateForm,
        child: const Icon(Icons.add),
      ),
    );
  }

  void _openCreateForm() {
    context.push(
      '/packages/form',
      extra: PackageFormArgs(initialScope: _scopeFilter),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected
              ? AppTheme.primaryColor.withValues(alpha: 0.12)
              : Colors.white,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected ? AppTheme.primaryColor : Colors.grey.shade200,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: selected ? AppTheme.primaryColor : Colors.grey.shade700,
          ),
        ),
      ),
    );
  }
}
