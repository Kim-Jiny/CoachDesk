import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import '../../providers/member_provider.dart';
import '../../widgets/common.dart';

class MemberListScreen extends ConsumerStatefulWidget {
  const MemberListScreen({super.key});

  @override
  ConsumerState<MemberListScreen> createState() => _MemberListScreenState();
}

class _MemberListScreenState extends ConsumerState<MemberListScreen> {
  final _searchController = TextEditingController();
  Timer? _searchDebounce;

  @override
  void initState() {
    super.initState();
    Future.microtask(() => ref.read(memberProvider.notifier).fetchMembers());
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final memberState = ref.watch(memberProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('회원 관리'),
      ),
      body: Column(
        children: [
          // Rounded search bar
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: AppTheme.softShadow,
              ),
              child: TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: '이름, 전화번호, 이메일로 검색',
                  hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 14),
                  prefixIcon: Icon(Icons.search_rounded, color: Colors.grey.shade400),
                  suffixIcon: _searchController.text.isNotEmpty
                      ? IconButton(
                          icon: Icon(Icons.clear_rounded, color: Colors.grey.shade400),
                          onPressed: () {
                            _searchController.clear();
                            ref.read(memberProvider.notifier).fetchMembers();
                            setState(() {});
                          },
                        )
                      : null,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                ),
                onChanged: (value) {
                  setState(() {});
                  _searchDebounce?.cancel();
                  _searchDebounce = Timer(const Duration(milliseconds: 300), () {
                    if (!mounted) return;
                    ref.read(memberProvider.notifier).fetchMembers(
                      search: value.trim().isEmpty ? null : value.trim(),
                    );
                  });
                },
              ),
            ),
          ),
          Expanded(
            child: memberState.isLoading
                ? const ShimmerLoading(style: ShimmerStyle.list)
                : memberState.members.isEmpty
                    ? EmptyState(
                        icon: Icons.people_outline,
                        message: _searchController.text.trim().isNotEmpty
                            ? '검색 결과가 없습니다'
                            : '등록된 회원이 없습니다',
                        actionLabel: _searchController.text.trim().isNotEmpty ? '검색 초기화' : '회원 등록',
                        onAction: () {
                          if (_searchController.text.trim().isNotEmpty) {
                            _searchController.clear();
                            ref.read(memberProvider.notifier).fetchMembers();
                            setState(() {});
                            return;
                          }
                          context.push('/members-form');
                        },
                      )
                    : RefreshIndicator(
                        onRefresh: () => ref.read(memberProvider.notifier).fetchMembers(),
                        child: ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          itemCount: memberState.members.length,
                          itemBuilder: (context, index) {
                            final member = memberState.members[index];
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: Container(
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(14),
                                  boxShadow: AppTheme.softShadow,
                                ),
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(14),
                                  onTap: () => context.push('/members/${member.id}'),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                                    child: Row(
                                      children: [
                                        CircleAvatar(
                                          radius: 22,
                                          backgroundColor: member.status == 'ACTIVE'
                                              ? AppTheme.primaryColor.withValues(alpha: 0.1)
                                              : Colors.grey.shade100,
                                          child: Text(
                                            member.name[0],
                                            style: TextStyle(
                                              color: member.status == 'ACTIVE'
                                                  ? AppTheme.primaryColor
                                                  : Colors.grey,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 14),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Row(
                                                children: [
                                                  Expanded(
                                                    child: Text(
                                                      member.name,
                                                      maxLines: 1,
                                                      overflow: TextOverflow.ellipsis,
                                                      style: const TextStyle(fontWeight: FontWeight.w600),
                                                    ),
                                                  ),
                                                  const SizedBox(width: 8),
                                                  Flexible(
                                                    child: Align(
                                                      alignment: Alignment.centerRight,
                                                      child: StatusBadge.fromStatus(member.status),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                              const SizedBox(height: 6),
                                              Text(
                                                member.phone ?? member.email ?? '',
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: TextStyle(color: Colors.grey.shade500, fontSize: 13),
                                              ),
                                              if (member.quickMemo != null && member.quickMemo!.isNotEmpty) ...[
                                                const SizedBox(height: 4),
                                                Text(
                                                  member.quickMemo!,
                                                  maxLines: 1,
                                                  overflow: TextOverflow.ellipsis,
                                                  style: TextStyle(
                                                    color: Colors.orange.shade700,
                                                    fontSize: 12,
                                                    fontWeight: FontWeight.w500,
                                                  ),
                                                ),
                                              ],
                                            ],
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Icon(Icons.chevron_right, color: Colors.grey.shade400),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => context.push('/members-form'),
        child: const Icon(Icons.person_add),
      ),
    );
  }
}
