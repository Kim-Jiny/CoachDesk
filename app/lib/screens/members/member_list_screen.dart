import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import '../../models/member.dart';
import '../../providers/member_provider.dart';
import '../../widgets/common.dart';

class MemberListScreen extends ConsumerStatefulWidget {
  const MemberListScreen({super.key});

  @override
  ConsumerState<MemberListScreen> createState() => _MemberListScreenState();
}

// Sentinel used to represent the "all groups" filter. Distinct from
// `null`, which represents the "미분류" (ungrouped) section.
const String _kAllGroupsFilter = '__all__';

class _MemberListScreenState extends ConsumerState<MemberListScreen> {
  final _searchController = TextEditingController();
  Timer? _searchDebounce;
  String? _dragTargetGroupId;
  String? _selectedGroupFilter = _kAllGroupsFilter;

  bool _isPackageActive(String status) => status == 'PACKAGE_ACTIVE';

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

  Future<void> _showCreateGroupDialog() async {
    final controller = TextEditingController();
    final created = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('그룹 추가'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: '그룹 이름',
            hintText: '예: 오전반, 신규회원, VIP',
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () {
              if (controller.text.trim().isEmpty) return;
              Navigator.pop(context, true);
            },
            child: const Text('추가'),
          ),
        ],
      ),
    );

    if (created != true || !mounted) return;

    final success = await ref
        .read(memberProvider.notifier)
        .createGroup(controller.text.trim());
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(success ? '그룹을 추가했습니다' : '그룹 추가에 실패했습니다')),
    );
  }

  Future<void> _moveMember(Member member, String? groupId) async {
    if (member.memberGroupId == groupId) {
      if (mounted) {
        setState(() => _dragTargetGroupId = null);
      }
      return;
    }

    final success = await ref
        .read(memberProvider.notifier)
        .moveMemberToGroup(member.id, groupId);
    if (!mounted) return;
    setState(() => _dragTargetGroupId = null);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          success
              ? groupId == null
                    ? '${member.name}님을 미분류로 이동했습니다'
                    : '${member.name}님을 그룹으로 이동했습니다'
              : '회원 이동에 실패했습니다',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final memberState = ref.watch(memberProvider);
    final groups = [...memberState.groups]
      ..sort((left, right) => left.sortOrder.compareTo(right.sortOrder));
    final groupedMembers = <String?, List<Member>>{};
    for (final member in memberState.members) {
      groupedMembers.putIfAbsent(member.memberGroupId, () => []);
      groupedMembers[member.memberGroupId]!.add(member);
    }

    final allSections = <_MemberGroupSection>[
      _MemberGroupSection(
        groupId: null,
        title: '미분류',
        members: groupedMembers[null] ?? [],
      ),
      ...groups.map(
        (group) => _MemberGroupSection(
          groupId: group.id,
          title: group.name,
          members: groupedMembers[group.id] ?? [],
        ),
      ),
    ];

    final sections = _selectedGroupFilter == _kAllGroupsFilter
        ? allSections
        : allSections
              .where((section) => section.groupId == _selectedGroupFilter)
              .toList();

    return Scaffold(
      appBar: AppBar(title: const Text('회원 관리')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: Column(
              children: [
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: AppTheme.softShadow,
                  ),
                  child: TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText: '이름, 전화번호, 이메일로 검색',
                      hintStyle: TextStyle(
                        color: Colors.grey.shade400,
                        fontSize: 14,
                      ),
                      prefixIcon: Icon(
                        Icons.search_rounded,
                        color: Colors.grey.shade400,
                      ),
                      suffixIcon: _searchController.text.isNotEmpty
                          ? IconButton(
                              icon: Icon(
                                Icons.clear_rounded,
                                color: Colors.grey.shade400,
                              ),
                              onPressed: () {
                                _searchController.clear();
                                ref
                                    .read(memberProvider.notifier)
                                    .fetchMembers();
                                setState(() {});
                              },
                            )
                          : null,
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 14,
                      ),
                    ),
                    onChanged: (value) {
                      setState(() {});
                      _searchDebounce?.cancel();
                      _searchDebounce = Timer(
                        const Duration(milliseconds: 300),
                        () {
                          if (!mounted) return;
                          ref
                              .read(memberProvider.notifier)
                              .fetchMembers(
                                search: value.trim().isEmpty
                                    ? null
                                    : value.trim(),
                              );
                        },
                      );
                    },
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  height: 36,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    children: [
                      _GroupFilterChip(
                        label: '전체',
                        count: memberState.members.length,
                        selected: _selectedGroupFilter == _kAllGroupsFilter,
                        onTap: () => setState(
                          () => _selectedGroupFilter = _kAllGroupsFilter,
                        ),
                      ),
                      const SizedBox(width: 8),
                      _GroupFilterChip(
                        label: '미분류',
                        count: (groupedMembers[null] ?? const []).length,
                        selected: _selectedGroupFilter == null,
                        onTap: () =>
                            setState(() => _selectedGroupFilter = null),
                      ),
                      for (final group in groups) ...[
                        const SizedBox(width: 8),
                        _GroupFilterChip(
                          label: group.name,
                          count: (groupedMembers[group.id] ?? const []).length,
                          selected: _selectedGroupFilter == group.id,
                          onTap: () =>
                              setState(() => _selectedGroupFilter = group.id),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '그룹에 길게 눌러 끌어서 회원을 옮길 수 있어요',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ),
                    OutlinedButton.icon(
                      onPressed: _showCreateGroupDialog,
                      icon: const Icon(Icons.create_new_folder_outlined),
                      label: const Text('그룹 추가'),
                    ),
                  ],
                ),
              ],
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
                    actionLabel: _searchController.text.trim().isNotEmpty
                        ? '검색 초기화'
                        : '회원 등록',
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
                    onRefresh: () =>
                        ref.read(memberProvider.notifier).fetchMembers(),
                    child: ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      itemCount: sections.length,
                      itemBuilder: (context, index) {
                        final section = sections[index];
                        return _MemberGroupPanel(
                          title: section.title,
                          count: section.members.length,
                          isActiveDragTarget:
                              _dragTargetGroupId == section.groupId,
                          onWillAccept: (member) {
                            if (member == null) return false;
                            if (member.memberGroupId == section.groupId) {
                              if (_dragTargetGroupId == section.groupId) {
                                setState(() => _dragTargetGroupId = null);
                              }
                              return false;
                            }
                            setState(
                              () => _dragTargetGroupId = section.groupId,
                            );
                            return true;
                          },
                          onLeave: (_) {
                            if (_dragTargetGroupId == section.groupId) {
                              setState(() => _dragTargetGroupId = null);
                            }
                          },
                          onAccept: (member) =>
                              _moveMember(member, section.groupId),
                          child: section.members.isEmpty
                              ? Padding(
                                  padding: const EdgeInsets.only(top: 8),
                                  child: Text(
                                    '이 그룹에는 회원이 없습니다',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey.shade500,
                                    ),
                                  ),
                                )
                              : Column(
                                  children: section.members.map((member) {
                                    return Padding(
                                      padding: const EdgeInsets.only(top: 8),
                                      child: LongPressDraggable<Member>(
                                        data: member,
                                        feedback: Material(
                                          color: Colors.transparent,
                                          child: SizedBox(
                                            width:
                                                MediaQuery.of(
                                                  context,
                                                ).size.width -
                                                48,
                                            child: Opacity(
                                              opacity: 0.92,
                                              child: _MemberCard(
                                                member: member,
                                                isPackageActive:
                                                    _isPackageActive(
                                                      member.packageStatus,
                                                    ),
                                                onTap: () {},
                                              ),
                                            ),
                                          ),
                                        ),
                                        childWhenDragging: Opacity(
                                          opacity: 0.35,
                                          child: _MemberCard(
                                            member: member,
                                            isPackageActive: _isPackageActive(
                                              member.packageStatus,
                                            ),
                                            onTap: () => context.push(
                                              '/members/${member.id}',
                                            ),
                                          ),
                                        ),
                                        child: _MemberCard(
                                          member: member,
                                          isPackageActive: _isPackageActive(
                                            member.packageStatus,
                                          ),
                                          onTap: () => context.push(
                                            '/members/${member.id}',
                                          ),
                                        ),
                                      ),
                                    );
                                  }).toList(),
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

class _MemberGroupSection {
  final String? groupId;
  final String title;
  final List<Member> members;

  const _MemberGroupSection({
    required this.groupId,
    required this.title,
    required this.members,
  });
}

class _GroupFilterChip extends StatelessWidget {
  final String label;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  const _GroupFilterChip({
    required this.label,
    required this.count,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: selected
              ? AppTheme.primaryColor.withValues(alpha: 0.12)
              : Colors.white,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected ? AppTheme.primaryColor : Colors.grey.shade200,
            width: selected ? 1.3 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: selected ? AppTheme.primaryColor : Colors.grey.shade700,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              '$count',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: selected
                    ? AppTheme.primaryColor.withValues(alpha: 0.8)
                    : Colors.grey.shade500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MemberGroupPanel extends StatelessWidget {
  final String title;
  final int count;
  final Widget child;
  final bool isActiveDragTarget;
  final bool Function(Member?) onWillAccept;
  final void Function(Member) onAccept;
  final void Function(Member?) onLeave;

  const _MemberGroupPanel({
    required this.title,
    required this.count,
    required this.child,
    required this.isActiveDragTarget,
    required this.onWillAccept,
    required this.onAccept,
    required this.onLeave,
  });

  @override
  Widget build(BuildContext context) {
    return DragTarget<Member>(
      onWillAcceptWithDetails: (details) => onWillAccept(details.data),
      onLeave: onLeave,
      onAcceptWithDetails: (details) => onAccept(details.data),
      builder: (context, candidateData, rejectedData) {
        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: isActiveDragTarget
                ? AppTheme.primaryColor.withValues(alpha: 0.06)
                : Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isActiveDragTarget
                  ? AppTheme.primaryColor
                  : Colors.grey.shade200,
              width: isActiveDragTarget ? 1.5 : 1,
            ),
            boxShadow: AppTheme.softShadow,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    title == '미분류'
                        ? Icons.folder_open_outlined
                        : Icons.folder_outlined,
                    size: 20,
                    color: isActiveDragTarget
                        ? AppTheme.primaryColor
                        : Colors.blueGrey,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  StatusBadge(label: '$count명', color: AppTheme.primaryColor),
                ],
              ),
              if (isActiveDragTarget) ...[
                const SizedBox(height: 8),
                Text(
                  '여기로 놓으면 이 그룹으로 이동합니다',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppTheme.primaryColor,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
              child,
            ],
          ),
        );
      },
    );
  }
}

class _MemberCard extends StatelessWidget {
  final Member member;
  final bool isPackageActive;
  final VoidCallback onTap;

  const _MemberCard({
    required this.member,
    required this.isPackageActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final contact = member.phone ?? member.email ?? '';

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade100),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
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
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Align(
                            alignment: Alignment.centerRight,
                            child: StatusBadge.fromStatus(member.packageStatus),
                          ),
                        ),
                      ],
                    ),
                    if (contact.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        contact,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.grey.shade500,
                          fontSize: 12,
                        ),
                      ),
                    ],
                    const SizedBox(height: 5),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        StatusBadge(
                          label: member.memberSourceLabel,
                          color: member.hasMemberAccount
                              ? AppTheme.primaryColor
                              : Colors.blueGrey,
                        ),
                        StatusBadge(
                          label: member.memberAccessLabel,
                          color: member.hasMemberAccount
                              ? Colors.orange
                              : Colors.grey,
                        ),
                      ],
                    ),
                    if (member.quickMemo != null &&
                        member.quickMemo!.isNotEmpty) ...[
                      const SizedBox(height: 3),
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
              const SizedBox(width: 6),
              Icon(Icons.drag_indicator_rounded, color: Colors.grey.shade400),
            ],
          ),
        ),
      ),
    );
  }
}
