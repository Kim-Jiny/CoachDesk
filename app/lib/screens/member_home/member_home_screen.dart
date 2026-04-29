import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/api_client.dart';
import '../../core/fcm_service.dart';
import '../../core/socket_service.dart';
import '../../core/theme.dart';
import '../../models/member_booking.dart';
import '../../models/package.dart';
import '../../providers/auth_provider.dart';
import '../../providers/chat_provider.dart';
import '../../providers/member_auth_provider.dart';
import '../../widgets/admin_register_dialog.dart';

class MemberHomeScreen extends ConsumerStatefulWidget {
  const MemberHomeScreen({super.key});

  @override
  ConsumerState<MemberHomeScreen> createState() => _MemberHomeScreenState();
}

class _MemberHomeScreenState extends ConsumerState<MemberHomeScreen> {
  List<MemberReservationSummary> _reservations = [];
  List<MemberPackage> _packages = [];
  bool _isLoadingReservations = false;
  bool _isLoadingPackages = false;
  AppLifecycleListener? _lifecycleListener;

  @override
  void initState() {
    super.initState();
    _lifecycleListener = AppLifecycleListener(onResume: _handleResume);
    FcmService.addReservationSyncListener(_handleReservationSync);
    _registerSocketListeners();
    Future.microtask(() {
      ref.read(memberAuthProvider.notifier).fetchMyClasses();
      ref.read(chatRoomListProvider.notifier).fetchRooms();
      _loadReservations();
      _loadPackages();
    });
  }

  @override
  void dispose() {
    _unregisterSocketListeners();
    FcmService.removeReservationSyncListener(_handleReservationSync);
    _lifecycleListener?.dispose();
    super.dispose();
  }

  void _onSocketReservationEvent(dynamic _) {
    if (!mounted) return;
    _loadReservations();
  }

  void _registerSocketListeners() {
    final socket = SocketService.instance;
    socket.on('reservation:created', _onSocketReservationEvent);
    socket.on('reservation:updated', _onSocketReservationEvent);
    socket.on('reservation:cancelled', _onSocketReservationEvent);
  }

  void _unregisterSocketListeners() {
    final socket = SocketService.instance;
    socket.off('reservation:created', _onSocketReservationEvent);
    socket.off('reservation:updated', _onSocketReservationEvent);
    socket.off('reservation:cancelled', _onSocketReservationEvent);
  }

  void _handleResume() {
    if (!mounted) return;
    _loadReservations();
  }

  void _handleReservationSync() {
    if (!mounted) return;
    _loadReservations();
  }

  Future<void> _openChatWithCoach(
    MemberClass memberClass,
    MemberCoach coach,
  ) async {
    final accountId = ref.read(memberAuthProvider).accountId;
    if (accountId == null) return;

    final messenger = ScaffoldMessenger.of(context);
    final router = GoRouter.of(context);

    final room = await ref
        .read(chatRoomListProvider.notifier)
        .getOrCreateRoom(
          organizationId: memberClass.organizationId,
          userId: coach.id,
          memberAccountId: accountId,
        );

    if (!mounted) return;
    if (room == null) {
      messenger.showSnackBar(const SnackBar(content: Text('채팅방을 열 수 없습니다')));
      return;
    }

    // Refresh list so the new room shows up with up-to-date metadata
    await ref.read(chatRoomListProvider.notifier).fetchRooms();
    if (!mounted) return;
    router.push('/member/chat/${room.id}');
  }

  Future<void> _loadReservations() async {
    setState(() => _isLoadingReservations = true);
    final result = await ref
        .read(memberAuthProvider.notifier)
        .fetchMyReservations();
    if (mounted) {
      setState(() {
        _reservations = result;
        _isLoadingReservations = false;
      });
    }
  }

  Future<void> _loadPackages() async {
    setState(() => _isLoadingPackages = true);
    final result = await ref
        .read(memberAuthProvider.notifier)
        .fetchMyPackages();
    if (mounted) {
      setState(() {
        _packages = result;
        _isLoadingPackages = false;
      });
    }
  }

  Future<void> _openPauseRequestSheet(MemberPackage memberPackage) async {
    DateTime? startDate;
    DateTime? endDate;
    final reasonController = TextEditingController();

    final submitted = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) {
          Future<void> pickStartDate() async {
            final picked = await showDatePicker(
              context: context,
              initialDate: DateTime.now(),
              firstDate: DateTime.now(),
              lastDate:
                  memberPackage.expiryDate ??
                  DateTime.now().add(const Duration(days: 365)),
            );
            if (picked == null) return;
            setModalState(() {
              startDate = picked;
              if (endDate != null && endDate!.isBefore(picked)) {
                endDate = picked;
              }
            });
          }

          Future<void> pickEndDate() async {
            final picked = await showDatePicker(
              context: context,
              initialDate: endDate ?? startDate ?? DateTime.now(),
              firstDate: startDate ?? DateTime.now(),
              lastDate:
                  memberPackage.expiryDate ??
                  DateTime.now().add(const Duration(days: 365)),
            );
            if (picked == null) return;
            setModalState(() => endDate = picked);
          }

          final canSubmit = startDate != null && endDate != null;
          final extensionDays = canSubmit
              ? endDate!.difference(startDate!).inDays + 1
              : null;

          return Padding(
            padding: EdgeInsets.only(
              left: 20,
              right: 20,
              top: 8,
              bottom: MediaQuery.of(context).viewInsets.bottom + 20,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${memberPackage.package?.name ?? '패키지'} 정지 신청',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '관리자 승인 후 선택한 기간만큼 만료일이 연장됩니다.',
                  style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                ),
                const SizedBox(height: 12),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.play_arrow_rounded),
                  title: const Text('정지 시작일'),
                  subtitle: Text(
                    startDate == null
                        ? '날짜 선택'
                        : DateFormat('yyyy.MM.dd').format(startDate!),
                  ),
                  onTap: pickStartDate,
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.stop_rounded),
                  title: const Text('정지 종료일'),
                  subtitle: Text(
                    endDate == null
                        ? '날짜 선택'
                        : DateFormat('yyyy.MM.dd').format(endDate!),
                  ),
                  onTap: pickEndDate,
                ),
                TextField(
                  controller: reasonController,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: '정지 사유',
                    hintText: '필요시 간단히 적어주세요',
                  ),
                ),
                if (extensionDays != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppTheme.primaryColor.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '승인되면 만료일이 $extensionDays일 연장됩니다.',
                      style: const TextStyle(
                        color: AppTheme.primaryColor,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: canSubmit
                        ? () => Navigator.pop(context, true)
                        : null,
                    child: const Text('정지 신청하기'),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );

    if (submitted != true || startDate == null || endDate == null || !mounted) {
      reasonController.dispose();
      return;
    }

    final message = await ref
        .read(memberAuthProvider.notifier)
        .requestPackagePause(
          memberPackageId: memberPackage.id,
          startDate: DateFormat('yyyy-MM-dd').format(startDate!),
          endDate: DateFormat('yyyy-MM-dd').format(endDate!),
          reason: reasonController.text,
        );
    reasonController.dispose();

    if (!mounted || message == null) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
    await _loadPackages();
  }

  void _showJoinDialog() {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('초대코드 입력'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            hintText: '선생님에게 받은 코드를 입력하세요',
            prefixIcon: Icon(Icons.vpn_key_outlined),
          ),
          textCapitalization: TextCapitalization.characters,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () async {
              final code = controller.text.trim();
              if (code.isEmpty) return;
              Navigator.pop(ctx);
              final success = await ref
                  .read(memberAuthProvider.notifier)
                  .joinClass(code);
              if (mounted) {
                final message = success
                    ? '수업에 참여했습니다!'
                    : (ref.read(memberAuthProvider).error ?? '참여에 실패했습니다');
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(message),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              }
            },
            child: const Text('참여하기'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(memberAuthProvider);
    final name = authState.name ?? '회원';
    final classes = authState.classes;
    final unreadCount = ref.watch(chatUnreadCountProvider);

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          // Gradient header
          SliverToBoxAdapter(
            child: Container(
              width: double.infinity,
              padding: EdgeInsets.only(
                top: MediaQuery.of(context).padding.top + 16,
                bottom: 24,
                left: 24,
                right: 24,
              ),
              decoration: const BoxDecoration(
                gradient: AppTheme.primaryGradient,
                borderRadius: BorderRadius.only(
                  bottomLeft: Radius.circular(32),
                  bottomRight: Radius.circular(32),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '$name님의 수업',
                              style: const TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${classes.length}개의 수업에 참여중',
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.white.withValues(alpha: 0.8),
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: () => context.push('/member/notifications'),
                        icon: Icon(
                          Icons.notifications_outlined,
                          color: Colors.white.withValues(alpha: 0.9),
                        ),
                        tooltip: '알림',
                      ),
                      IconButton(
                        onPressed: () => context.push('/member/chat'),
                        icon: Badge(
                          isLabelVisible: unreadCount > 0,
                          label: Text(
                            unreadCount > 99 ? '99+' : '$unreadCount',
                          ),
                          child: Icon(
                            Icons.chat_bubble_outline,
                            color: Colors.white.withValues(alpha: 0.9),
                          ),
                        ),
                        tooltip: '채팅',
                      ),
                      PopupMenuButton<String>(
                        icon: Icon(
                          Icons.more_vert,
                          color: Colors.white.withValues(alpha: 0.9),
                        ),
                        onSelected: (value) async {
                          if (value == 'switch_admin') {
                            final hasAdminToken =
                                ApiClient.getAdminAccessToken() != null;
                            if (hasAdminToken) {
                              final switched = await ref
                                  .read(authProvider.notifier)
                                  .switchFromMember();
                              if (!switched && context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('관리자 모드로 전환할 수 없습니다'),
                                    behavior: SnackBarBehavior.floating,
                                  ),
                                );
                              }
                              // Router redirect navigates based on center state
                            } else {
                              await showDialog<bool>(
                                context: context,
                                builder: (_) => const AdminRegisterDialog(),
                              );
                              // Router redirect navigates based on center state
                            }
                          } else if (value == 'logout') {
                            await ref
                                .read(memberAuthProvider.notifier)
                                .logout();
                            if (!context.mounted) return;
                            context.go('/auth-select');
                          } else if (value == 'notification_settings') {
                            context.push('/member/settings');
                          }
                        },
                        itemBuilder: (_) => [
                          const PopupMenuItem(
                            value: 'notification_settings',
                            child: Row(
                              children: [
                                Icon(Icons.notifications_outlined, size: 20),
                                SizedBox(width: 8),
                                Text('앱 설정'),
                              ],
                            ),
                          ),
                          const PopupMenuItem(
                            value: 'switch_admin',
                            child: Row(
                              children: [
                                Icon(Icons.swap_horiz, size: 20),
                                SizedBox(width: 8),
                                Text('관리자 모드로 전환'),
                              ],
                            ),
                          ),
                          const PopupMenuItem(
                            value: 'logout',
                            child: Row(
                              children: [
                                Icon(Icons.logout, size: 20),
                                SizedBox(width: 8),
                                Text('로그아웃'),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          // Upcoming reservations
          if (_reservations.isNotEmpty) ...[
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
                child: Row(
                  children: [
                    const Text(
                      '다가오는 예약',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: AppTheme.primaryColor.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '${_reservations.length}',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.primaryColor,
                        ),
                      ),
                    ),
                    const Spacer(),
                    GestureDetector(
                      onTap: () => context.push('/member/history'),
                      child: Text(
                        '전체 보기',
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: SizedBox(
                height: 96,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  itemCount: _reservations.length > 5
                      ? 5
                      : _reservations.length,
                  itemBuilder: (context, index) {
                    final r = _reservations[index];
                    return Container(
                      width: 200,
                      margin: const EdgeInsets.only(right: 10),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: AppTheme.softShadow,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  DateFormat('M/d (E)', 'ko').format(r.date),
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: r.status == 'CONFIRMED'
                                      ? Colors.green.withValues(alpha: 0.1)
                                      : Colors.orange.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  r.status == 'CONFIRMED' ? '확정' : '대기',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w600,
                                    color: r.status == 'CONFIRMED'
                                        ? Colors.green.shade700
                                        : Colors.orange.shade700,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${r.startTime} - ${r.endTime}  ${r.coachName} 코치',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade600,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            r.organizationName,
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.grey.shade400,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),
          ] else if (!_isLoadingReservations && classes.isNotEmpty)
            const SliverToBoxAdapter(child: SizedBox.shrink()),

          if (_packages.isNotEmpty || _isLoadingPackages)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '내 패키지',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (_isLoadingPackages)
                      const Center(
                        child: Padding(
                          padding: EdgeInsets.symmetric(vertical: 16),
                          child: CircularProgressIndicator(),
                        ),
                      )
                    else
                      ..._packages.map((memberPackage) {
                        final expiryLabel = memberPackage.expiryDate == null
                            ? '무제한'
                            : DateFormat(
                                'yyyy.MM.dd',
                              ).format(memberPackage.expiryDate!);
                        final pendingRange =
                            memberPackage.pauseRequestedStartDate != null &&
                                memberPackage.pauseRequestedEndDate != null
                            ? '${DateFormat('M/d').format(memberPackage.pauseRequestedStartDate!)} - ${DateFormat('M/d').format(memberPackage.pauseRequestedEndDate!)}'
                            : null;
                        final activeRange =
                            memberPackage.pauseStartDate != null &&
                                memberPackage.pauseEndDate != null
                            ? '${DateFormat('M/d').format(memberPackage.pauseStartDate!)} - ${DateFormat('M/d').format(memberPackage.pauseEndDate!)}'
                            : null;

                        return GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () async {
                            await context.push(
                              '/member/packages/${memberPackage.id}',
                            );
                            _loadPackages();
                          },
                          child: Container(
                            margin: const EdgeInsets.only(bottom: 10),
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(16),
                              boxShadow: AppTheme.softShadow,
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        memberPackage.package?.name ?? '패키지',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w700,
                                          fontSize: 15,
                                        ),
                                      ),
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 10,
                                        vertical: 4,
                                      ),
                                      decoration: BoxDecoration(
                                        color: memberPackage.isCurrentlyPaused
                                            ? Colors.orange.withValues(
                                                alpha: 0.12,
                                              )
                                            : AppTheme.primaryColor.withValues(
                                                alpha: 0.1,
                                              ),
                                        borderRadius: BorderRadius.circular(
                                          999,
                                        ),
                                      ),
                                      child: Text(
                                        memberPackage.isCurrentlyPaused
                                            ? '정지 중'
                                            : '이용 중',
                                        style: TextStyle(
                                          color: memberPackage.isCurrentlyPaused
                                              ? Colors.orange.shade700
                                              : AppTheme.primaryColor,
                                          fontWeight: FontWeight.w600,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  memberPackage.organizationName ?? '',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey.shade500,
                                  ),
                                ),
                                const SizedBox(height: 10),
                                Text(
                                  '잔여 ${memberPackage.remainingSessions}/${memberPackage.totalSessions}회',
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: Colors.grey.shade700,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '현재 만료일: $expiryLabel',
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: Colors.grey.shade700,
                                  ),
                                ),
                                if (memberPackage.pauseExtensionDays > 0) ...[
                                  const SizedBox(height: 4),
                                  Text(
                                    '정지 승인으로 총 ${memberPackage.pauseExtensionDays}일 연장됨',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.blueGrey.shade600,
                                    ),
                                  ),
                                ],
                                if (memberPackage.hasPendingPauseRequest &&
                                    pendingRange != null) ...[
                                  const SizedBox(height: 10),
                                  Container(
                                    width: double.infinity,
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: Colors.orange.withValues(
                                        alpha: 0.08,
                                      ),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Text(
                                      '정지 신청 검토 중: $pendingRange',
                                      style: TextStyle(
                                        color: Colors.orange.shade800,
                                        fontWeight: FontWeight.w600,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ),
                                ],
                                if (memberPackage.isCurrentlyPaused &&
                                    activeRange != null) ...[
                                  const SizedBox(height: 10),
                                  Container(
                                    width: double.infinity,
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: Colors.orange.withValues(
                                        alpha: 0.08,
                                      ),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Text(
                                      '현재 정지 기간: $activeRange',
                                      style: TextStyle(
                                        color: Colors.orange.shade800,
                                        fontWeight: FontWeight.w600,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ),
                                ],
                                const SizedBox(height: 12),
                                SizedBox(
                                  width: double.infinity,
                                  child: OutlinedButton(
                                    onPressed:
                                        memberPackage.status != 'ACTIVE' ||
                                            memberPackage
                                                .hasPendingPauseRequest ||
                                            memberPackage.isCurrentlyPaused
                                        ? null
                                        : () => _openPauseRequestSheet(
                                            memberPackage,
                                          ),
                                    child: Text(
                                      memberPackage.hasPendingPauseRequest
                                          ? '정지 신청 검토중'
                                          : memberPackage.isCurrentlyPaused
                                          ? '현재 정지 중'
                                          : '패키지 정지 신청',
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      }),
                  ],
                ),
              ),
            ),

          // My classes header
          if (classes.isNotEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 4),
                child: const Text(
                  '내 수업',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                ),
              ),
            ),

          // Content
          if (classes.isEmpty)
            SliverFillRemaining(child: _EmptyState(onJoin: _showJoinDialog))
          else
            SliverPadding(
              padding: const EdgeInsets.all(20),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _ClassCard(
                      memberClass: classes[index],
                      onTap: () async {
                        await context.push(
                          '/member/class/${classes[index].organizationId}',
                          extra: classes[index].organizationName,
                        );
                        if (mounted) {
                          _loadReservations();
                          _loadPackages();
                        }
                      },
                      onCoachTap: (coach) =>
                          _openChatWithCoach(classes[index], coach),
                    ),
                  ),
                  childCount: classes.length,
                ),
              ),
            ),
        ],
      ),
      floatingActionButton: classes.isNotEmpty
          ? FloatingActionButton.extended(
              heroTag: 'member_home_join_class_fab',
              onPressed: _showJoinDialog,
              icon: const Icon(Icons.add),
              label: const Text('수업 참여'),
            )
          : null,
    );
  }
}

class _EmptyState extends StatelessWidget {
  final VoidCallback onJoin;

  const _EmptyState({required this.onJoin});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight - 64),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: AppTheme.primaryColor.withValues(alpha: 0.08),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.school_outlined,
                  size: 64,
                    color: AppTheme.primaryColor.withValues(alpha: 0.5),
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                '참여 중인 수업이 없습니다',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: Colors.black87,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '선생님에게 받은 초대코드로\n수업에 참여해보세요',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey.shade600,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 32),
              Container(
                decoration: BoxDecoration(
                  gradient: AppTheme.primaryGradient,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: AppTheme.primaryColor.withValues(alpha: 0.3),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: ElevatedButton.icon(
                  onPressed: onJoin,
                  icon: const Icon(Icons.vpn_key_outlined),
                  label: const Text('초대코드로 수업 찾기'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.transparent,
                    shadowColor: Colors.transparent,
                    minimumSize: const Size(220, 52),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 16,
                children: [
                  TextButton.icon(
                    onPressed: () => context.push('/member/settings'),
                    icon: const Icon(Icons.settings_outlined, size: 18),
                    label: const Text('앱 설정'),
                  ),
                  TextButton.icon(
                    onPressed: () => context.push('/member/settings'),
                    icon: const Icon(
                      Icons.delete_forever_outlined,
                      size: 18,
                      color: Colors.red,
                    ),
                    label: const Text(
                      '회원 탈퇴',
                      style: TextStyle(color: Colors.red),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ClassCard extends StatelessWidget {
  final MemberClass memberClass;
  final VoidCallback? onTap;
  final void Function(MemberCoach coach)? onCoachTap;

  const _ClassCard({required this.memberClass, this.onTap, this.onCoachTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: AppTheme.softShadow,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.fitness_center,
                    color: AppTheme.primaryColor,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    memberClass.organizationName,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: Colors.black87,
                    ),
                  ),
                ),
              ],
            ),
            if (memberClass.coaches.isNotEmpty) ...[
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: memberClass.coaches.map((coach) {
                  return ActionChip(
                    onPressed: onCoachTap == null
                        ? null
                        : () => onCoachTap!(coach),
                    avatar: CircleAvatar(
                      backgroundColor: AppTheme.primaryColor.withValues(
                        alpha: 0.15,
                      ),
                      child: Text(
                        coach.name.isNotEmpty ? coach.name[0] : '?',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.primaryColor,
                        ),
                      ),
                    ),
                    label: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(coach.name, style: const TextStyle(fontSize: 13)),
                        const SizedBox(width: 4),
                        Icon(
                          Icons.chat_bubble_outline,
                          size: 14,
                          color: Colors.grey.shade600,
                        ),
                      ],
                    ),
                    backgroundColor: Colors.grey.shade50,
                  );
                }).toList(),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
