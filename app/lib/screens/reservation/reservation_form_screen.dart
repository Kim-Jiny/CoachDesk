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

    return DismissKeyboardOnTap(child: Scaffold(
      appBar: AppBar(title: const Text('예약 등록')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Date
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.calendar_today),
                title: const Text('날짜'),
                subtitle: Text(
                  DateFormat('yyyy년 M월 d일 (E)', 'ko').format(_selectedDate),
                ),
                onTap: () async {
                  final date = await showDatePicker(
                    context: context,
                    initialDate: _selectedDate,
                    firstDate: DateTime.now().subtract(
                      const Duration(days: 30),
                    ),
                    lastDate: DateTime.now().add(const Duration(days: 365)),
                  );
                  if (date != null) {
                    setState(() => _selectedDate = date);
                    await _loadAvailableSlots();
                  }
                },
              ),
              const Divider(),

              Row(
                children: [
                  const Icon(Icons.event_available, size: 18),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      '오픈된 시간 선택',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: () =>
                        setState(() => _useManualTime = !_useManualTime),
                    child: Text(_useManualTime ? '직접 입력 중' : '직접 입력'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
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
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '선택한 날짜에 오픈된 시간대가 없습니다. 직접 입력으로 예약할 수 있습니다.',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                  ),
                )
              else
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
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
                        selectedColor: AppTheme.primaryColor.withValues(
                          alpha: 0.18,
                        ),
                      );
                    }),
                    ChoiceChip(
                      label: const Text('직접 입력'),
                      selected: _useManualTime,
                      onSelected: (_) => setState(() => _useManualTime = true),
                    ),
                  ],
                ),
              const SizedBox(height: 12),

              // Time
              if (_useManualTime)
                Row(
                  children: [
                    Expanded(
                      child: ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.access_time),
                        title: const Text('시작'),
                        subtitle: Text(_formatTime(_startTime)),
                        onTap: () async {
                          final time = await showTimePicker(
                            context: context,
                            initialTime: _startTime,
                          );
                          if (time != null) setState(() => _startTime = time);
                        },
                      ),
                    ),
                    Expanded(
                      child: ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.access_time),
                        title: const Text('종료'),
                        subtitle: Text(_formatTime(_endTime)),
                        onTap: () async {
                          final time = await showTimePicker(
                            context: context,
                            initialTime: _endTime,
                          );
                          if (time != null) setState(() => _endTime = time);
                        },
                      ),
                    ),
                  ],
                )
              else
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.schedule_rounded),
                  title: Text(
                    '${_formatTime(_startTime)} - ${_formatTime(_endTime)}',
                  ),
                  subtitle: Text(_selectedSlotCoachName() ?? '선택한 오픈 시간'),
                ),
              const Divider(),

              // Member selection
              const SizedBox(height: 8),
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
              if (_restoredRecentDefaults && selectedMember != null) ...[
                const SizedBox(height: 10),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.blueGrey.shade50,
                    borderRadius: BorderRadius.circular(12),
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
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 16),

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
              const SizedBox(height: 32),

              ElevatedButton(onPressed: _save, child: const Text('예약 등록')),
            ],
          ),
        ),
      ),
    ));
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
