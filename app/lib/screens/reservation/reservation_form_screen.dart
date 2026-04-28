import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:intl/intl.dart';

import '../../core/api_client.dart';
import '../../core/constants.dart';
import '../../core/theme.dart';
import '../../providers/member_provider.dart';
import '../../widgets/common.dart';
import '../../providers/reservation_provider.dart';
import '../../models/member.dart';

class ReservationFormScreen extends ConsumerStatefulWidget {
  final Map<String, dynamic>? initialData;

  const ReservationFormScreen({super.key, this.initialData});

  @override
  ConsumerState<ReservationFormScreen> createState() =>
      _ReservationFormScreenState();
}

class _ReservationFormScreenState extends ConsumerState<ReservationFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late DateTime _selectedDate;
  TimeOfDay _startTime = const TimeOfDay(hour: 9, minute: 0);
  TimeOfDay _endTime = const TimeOfDay(hour: 10, minute: 0);
  String? _coachId;
  Member? _selectedMember;
  String? _lastMemberId;
  String? _initialMemberId;
  bool _restoredRecentDefaults = false;
  bool _isLoadingSlots = false;
  bool _useManualTime = true;
  List<_AdminSlotOption> _availableSlots = [];
  final _quickMemoController = TextEditingController();
  final _memoController = TextEditingController();

  @override
  void initState() {
    super.initState();
    final dateStr = widget.initialData?['date'] as String?;
    _selectedDate = dateStr != null ? DateTime.parse(dateStr) : DateTime.now();
    _initialMemberId = widget.initialData?['memberId'] as String?;
    final startTime = widget.initialData?['startTime'] as String?;
    final endTime = widget.initialData?['endTime'] as String?;
    _coachId = widget.initialData?['coachId'] as String?;
    if (startTime != null) {
      _startTime = _parseTime(startTime);
    }
    if (endTime != null) {
      _endTime = _parseTime(endTime);
    }
    final authBox = Hive.box(AppConstants.authBox);
    _lastMemberId =
        authBox.get(AppConstants.reservationLastMemberIdKey) as String?;
    final savedStart =
        authBox.get(AppConstants.reservationLastStartTimeKey) as String?;
    final savedEnd =
        authBox.get(AppConstants.reservationLastEndTimeKey) as String?;
    if (startTime == null && savedStart != null) {
      _startTime = _parseTime(savedStart);
    }
    if (endTime == null && savedEnd != null) {
      _endTime = _parseTime(savedEnd);
    }
    _useManualTime = startTime == null || endTime == null;
    Future.microtask(() async {
      await ref.read(memberProvider.notifier).fetchMembers();
      final members = ref.read(memberProvider).members;
      if (_initialMemberId != null) {
        for (final member in members) {
          if (member.id == _initialMemberId) {
            _selectedMember = member;
            break;
          }
        }
      }
      if (mounted) {
        setState(() {});
      }
      await _loadAvailableSlots();
    });
  }

  @override
  void dispose() {
    _quickMemoController.dispose();
    _memoController.dispose();
    super.dispose();
  }

  String _formatTime(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  TimeOfDay _parseTime(String value) {
    final parts = value.split(':').map(int.parse).toList();
    return TimeOfDay(hour: parts[0], minute: parts[1]);
  }

  Member? _resolveSelectedMember(List<Member> members) {
    if (_selectedMember != null) return _selectedMember;
    if (_initialMemberId != null) {
      for (final member in members) {
        if (member.id == _initialMemberId) {
          return member;
        }
      }
    }
    if (_lastMemberId == null) return null;

    for (final member in members) {
      if (member.id == _lastMemberId) {
        _restoredRecentDefaults = true;
        return member;
      }
    }
    return null;
  }

  Future<void> _loadAvailableSlots() async {
    setState(() => _isLoadingSlots = true);
    try {
      final dio = ref.read(dioProvider);
      final response = await dio.get(
        '/schedules/slots',
        queryParameters: {
          'date': DateFormat('yyyy-MM-dd').format(_selectedDate),
        },
      );

      final slots =
          (response.data as List)
              .map(
                (json) =>
                    _AdminSlotOption.fromJson(json as Map<String, dynamic>),
              )
              .where((slot) => slot.available)
              .toList()
            ..sort((left, right) {
              final timeCompare = left.startTime.compareTo(right.startTime);
              if (timeCompare != 0) return timeCompare;
              return left.coachName.compareTo(right.coachName);
            });

      if (!mounted) return;
      setState(() {
        _availableSlots = slots;
        if (slots.isNotEmpty &&
            widget.initialData?['startTime'] == null &&
            widget.initialData?['endTime'] == null) {
          _useManualTime = false;
        }
        _isLoadingSlots = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _availableSlots = [];
        _isLoadingSlots = false;
      });
    }
  }

  void _applySlot(_AdminSlotOption slot) {
    setState(() {
      _coachId = slot.coachId;
      _startTime = _parseTime(slot.startTime);
      _endTime = _parseTime(slot.endTime);
      _useManualTime = false;
    });
  }

  String? _selectedSlotCoachName() {
    for (final slot in _availableSlots) {
      if (slot.coachId == _coachId &&
          slot.startTime == _formatTime(_startTime) &&
          slot.endTime == _formatTime(_endTime)) {
        return slot.coachName;
      }
    }
    return null;
  }

  bool _overlapsTimeRange(
    String leftStart,
    String leftEnd,
    String rightStart,
    String rightEnd,
  ) {
    return leftStart.compareTo(rightEnd) < 0 &&
        rightStart.compareTo(leftEnd) < 0;
  }

  List<_AdminSlotOption> _findOverlappingOpenSlots() {
    final effectiveCoachId = _coachId ?? ApiClient.getUserId();
    if (effectiveCoachId == null) return const [];
    final startTime = _formatTime(_startTime);
    final endTime = _formatTime(_endTime);

    return _availableSlots.where((slot) {
      if (slot.coachId != effectiveCoachId) return false;
      return _overlapsTimeRange(
        startTime,
        endTime,
        slot.startTime,
        slot.endTime,
      );
    }).toList();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final selectedMember =
        _selectedMember ??
        _resolveSelectedMember(ref.read(memberProvider).members);
    if (selectedMember == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('회원을 선택하세요')));
      return;
    }

    final overlappingOpenSlots = _useManualTime
        ? _findOverlappingOpenSlots()
        : const <_AdminSlotOption>[];
    var force = false;
    if (overlappingOpenSlots.isNotEmpty) {
      final overlapsSummary = overlappingOpenSlots
          .map((slot) => '${slot.startTime}-${slot.endTime} ${slot.coachName}')
          .join('\n');
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('이미 개설된 시간과 겹쳐요'),
          content: Text(
            '직접 입력한 시간이 아래 오픈 시간과 겹칩니다.\n\n$overlapsSummary\n\n그래도 예약을 추가하시겠어요?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('취소'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('그래도 추가'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
      force = true;
    }

    final result = await ref
        .read(reservationProvider.notifier)
        .createReservation({
          'memberId': selectedMember.id,
          'date': DateFormat('yyyy-MM-dd').format(_selectedDate),
          'startTime': _formatTime(_startTime),
          'endTime': _formatTime(_endTime),
          'manualTime': _useManualTime,
          'force': force,
          if (_coachId != null && _coachId!.isNotEmpty) 'coachId': _coachId,
          if (_quickMemoController.text.isNotEmpty)
            'quickMemo': _quickMemoController.text,
          if (_memoController.text.isNotEmpty) 'memo': _memoController.text,
        });

    if (!mounted) return;
    if (result.success) {
      final authBox = Hive.box(AppConstants.authBox);
      await authBox.put(
        AppConstants.reservationLastMemberIdKey,
        selectedMember.id,
      );
      await authBox.put(
        AppConstants.reservationLastStartTimeKey,
        _formatTime(_startTime),
      );
      await authBox.put(
        AppConstants.reservationLastEndTimeKey,
        _formatTime(_endTime),
      );
      if (!mounted) return;
      context.pop();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result.error ?? '예약에 실패했습니다. 정원이 가득 찼을 수 있습니다.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final memberState = ref.watch(memberProvider);
    final selectedMember = _resolveSelectedMember(memberState.members);
    final dateLabel = DateFormat('yyyy년 M월 d일 (E)', 'ko').format(_selectedDate);
    final selectedSlotCoachName = _selectedSlotCoachName();

    return DismissKeyboardOnTap(
      child: Scaffold(
        appBar: AppBar(title: const Text('회원 예약 등록')),
        body: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppTheme.primaryColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: const Icon(
                        Icons.person_add_alt_rounded,
                        color: AppTheme.primaryColor,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            '회원 예약 등록',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            dateLabel,
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.grey.shade600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryColor.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: AppTheme.primaryColor.withValues(alpha: 0.16),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.info_outline_rounded,
                        size: 20,
                        color: Colors.indigo.shade700,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          '오픈된 빈 타임을 바로 예약으로 연결하거나, 필요하면 시간을 직접 입력해서 등록할 수 있어요.',
                          style: TextStyle(
                            height: 1.35,
                            fontSize: 13,
                            color: Colors.indigo.shade900,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                _ReservationSectionCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _ReservationSectionHeader(
                        icon: Icons.calendar_today_rounded,
                        title: '예약 날짜',
                        actionLabel: '변경',
                        onActionTap: () async {
                          final date = await showDatePicker(
                            context: context,
                            initialDate: _selectedDate,
                            firstDate: DateTime.now().subtract(
                              const Duration(days: 30),
                            ),
                            lastDate: DateTime.now().add(
                              const Duration(days: 365),
                            ),
                          );
                          if (date != null) {
                            setState(() => _selectedDate = date);
                            await _loadAvailableSlots();
                          }
                        },
                      ),
                      const SizedBox(height: 10),
                      Text(
                        dateLabel,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                _ReservationSectionCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _ReservationSectionHeader(
                        icon: Icons.event_available_rounded,
                        title: '예약 시간 선택',
                        actionLabel: _useManualTime ? '오픈 타임 사용' : '직접 입력',
                        onActionTap: () =>
                            setState(() => _useManualTime = !_useManualTime),
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          ChoiceChip(
                            label: const Text('오픈 타임'),
                            selected: !_useManualTime,
                            onSelected: (_) =>
                                setState(() => _useManualTime = false),
                          ),
                          ChoiceChip(
                            label: const Text('직접 입력'),
                            selected: _useManualTime,
                            onSelected: (_) =>
                                setState(() => _useManualTime = true),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      if (_isLoadingSlots)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 12),
                          child: Center(child: CircularProgressIndicator()),
                        )
                      else if (_availableSlots.isEmpty)
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade50,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: Colors.grey.shade200),
                          ),
                          child: Text(
                            '선택한 날짜에 오픈된 시간대가 없습니다. 직접 입력으로 예약할 수 있습니다.',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade700,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        )
                      else
                        Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          children: [
                            ..._availableSlots.map((slot) {
                              final isSelected =
                                  !_useManualTime &&
                                  _coachId == slot.coachId &&
                                  _formatTime(_startTime) == slot.startTime &&
                                  _formatTime(_endTime) == slot.endTime;
                              return ChoiceChip(
                                label: Text(
                                  '${slot.startTime}-${slot.endTime}\n${slot.coachName}',
                                  textAlign: TextAlign.center,
                                ),
                                selected: isSelected,
                                onSelected: (_) => _applySlot(slot),
                                labelStyle: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  color: isSelected
                                      ? AppTheme.primaryColor
                                      : Colors.grey.shade800,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                  side: BorderSide(
                                    color: isSelected
                                        ? AppTheme.primaryColor.withValues(
                                            alpha: 0.24,
                                          )
                                        : Colors.grey.shade200,
                                  ),
                                ),
                                backgroundColor: Colors.white,
                                selectedColor: AppTheme.primaryColor.withValues(
                                  alpha: 0.12,
                                ),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 10,
                                ),
                              );
                            }),
                          ],
                        ),
                      const SizedBox(height: 14),
                      if (_useManualTime)
                        Row(
                          children: [
                            Expanded(
                              child: _ReservationTimePickCard(
                                label: '시작',
                                value: _formatTime(_startTime),
                                icon: Icons.play_arrow_rounded,
                                onTap: () async {
                                  final time = await showTimePicker(
                                    context: context,
                                    initialTime: _startTime,
                                  );
                                  if (time != null) {
                                    setState(() => _startTime = time);
                                  }
                                },
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _ReservationTimePickCard(
                                label: '종료',
                                value: _formatTime(_endTime),
                                icon: Icons.flag_rounded,
                                onTap: () async {
                                  final time = await showTimePicker(
                                    context: context,
                                    initialTime: _endTime,
                                  );
                                  if (time != null) {
                                    setState(() => _endTime = time);
                                  }
                                },
                              ),
                            ),
                          ],
                        )
                      else
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(color: Colors.grey.shade200),
                            boxShadow: AppTheme.softShadow,
                          ),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: AppTheme.primaryColor.withValues(
                                    alpha: 0.08,
                                  ),
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                child: const Icon(
                                  Icons.schedule_rounded,
                                  color: AppTheme.primaryColor,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '${_formatTime(_startTime)} - ${_formatTime(_endTime)}',
                                      style: const TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      selectedSlotCoachName ?? '선택한 오픈 시간',
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: Colors.grey.shade600,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                _ReservationSectionCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const _ReservationSectionHeader(
                        icon: Icons.person_outline_rounded,
                        title: '회원 선택',
                      ),
                      const SizedBox(height: 14),
                      DropdownButtonFormField<Member>(
                        decoration: const InputDecoration(
                          labelText: '회원 선택 *',
                          prefixIcon: Icon(Icons.person_outline),
                        ),
                        initialValue: selectedMember,
                        items: memberState.members.map((m) {
                          return DropdownMenuItem(
                            value: m,
                            child: Text(
                              '${m.name}${m.phone != null ? ' (${m.phone})' : ''}',
                            ),
                          );
                        }).toList(),
                        onChanged: (v) => setState(() => _selectedMember = v),
                        validator: (v) => v == null ? '회원을 선택하세요' : null,
                      ),
                      if (_restoredRecentDefaults &&
                          selectedMember != null) ...[
                        const SizedBox(height: 10),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: Colors.blueGrey.shade50,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.history,
                                size: 18,
                                color: Colors.blueGrey.shade400,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  '최근 예약 설정을 불러왔습니다',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.blueGrey.shade600,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                _ReservationSectionCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const _ReservationSectionHeader(
                        icon: Icons.edit_note_rounded,
                        title: '메모',
                      ),
                      const SizedBox(height: 14),
                      TextFormField(
                        controller: _quickMemoController,
                        decoration: const InputDecoration(
                          labelText: '카드 메모',
                          helperText: '스케줄 카드에서 바로 보이는 짧은 메모',
                          prefixIcon: Icon(Icons.short_text_rounded),
                        ),
                        maxLines: 2,
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _memoController,
                        decoration: const InputDecoration(
                          labelText: '상세 메모',
                          helperText: '예약 상세/완료 시 참고할 메모',
                          prefixIcon: Icon(Icons.note_outlined),
                        ),
                        maxLines: 2,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => context.pop(),
                        child: const Text('취소'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: FilledButton.icon(
                        onPressed: _save,
                        icon: const Icon(Icons.check_circle_outline_rounded),
                        label: const Text('회원 예약 등록'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ReservationSectionCard extends StatelessWidget {
  final Widget child;

  const _ReservationSectionCard({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: AppTheme.softShadow,
      ),
      child: child,
    );
  }
}

class _ReservationSectionHeader extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? actionLabel;
  final VoidCallback? onActionTap;

  const _ReservationSectionHeader({
    required this.icon,
    required this.title,
    this.actionLabel,
    this.onActionTap,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: AppTheme.primaryColor),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            title,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
          ),
        ),
        if (actionLabel != null && onActionTap != null)
          TextButton(onPressed: onActionTap, child: Text(actionLabel!)),
      ],
    );
  }
}

class _ReservationTimePickCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final VoidCallback onTap;

  const _ReservationTimePickCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.grey.shade200),
          boxShadow: AppTheme.softShadow,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 18, color: AppTheme.primaryColor),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.grey.shade600,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              value,
              style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800),
            ),
          ],
        ),
      ),
    );
  }
}

class _AdminSlotOption {
  final String coachId;
  final String coachName;
  final String startTime;
  final String endTime;
  final bool available;

  const _AdminSlotOption({
    required this.coachId,
    required this.coachName,
    required this.startTime,
    required this.endTime,
    required this.available,
  });

  factory _AdminSlotOption.fromJson(Map<String, dynamic> json) {
    return _AdminSlotOption(
      coachId: json['coachId'] as String,
      coachName: json['coachName'] as String? ?? '',
      startTime: json['startTime'] as String,
      endTime: json['endTime'] as String,
      available: json['available'] as bool? ?? false,
    );
  }
}
