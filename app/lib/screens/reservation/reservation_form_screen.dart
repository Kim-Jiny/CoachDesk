import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:intl/intl.dart';

import '../../core/constants.dart';
import '../../providers/member_provider.dart';
import '../../providers/reservation_provider.dart';
import '../../models/member.dart';

class ReservationFormScreen extends ConsumerStatefulWidget {
  final Map<String, dynamic>? initialData;

  const ReservationFormScreen({super.key, this.initialData});

  @override
  ConsumerState<ReservationFormScreen> createState() => _ReservationFormScreenState();
}

class _ReservationFormScreenState extends ConsumerState<ReservationFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late DateTime _selectedDate;
  TimeOfDay _startTime = const TimeOfDay(hour: 9, minute: 0);
  TimeOfDay _endTime = const TimeOfDay(hour: 10, minute: 0);
  Member? _selectedMember;
  String? _lastMemberId;
  bool _restoredRecentDefaults = false;
  final _quickMemoController = TextEditingController();
  final _memoController = TextEditingController();

  @override
  void initState() {
    super.initState();
    final dateStr = widget.initialData?['date'] as String?;
    _selectedDate = dateStr != null ? DateTime.parse(dateStr) : DateTime.now();
    final authBox = Hive.box(AppConstants.authBox);
    _lastMemberId = authBox.get(AppConstants.reservationLastMemberIdKey) as String?;
    final savedStart = authBox.get(AppConstants.reservationLastStartTimeKey) as String?;
    final savedEnd = authBox.get(AppConstants.reservationLastEndTimeKey) as String?;
    if (savedStart != null) {
      _startTime = _parseTime(savedStart);
    }
    if (savedEnd != null) {
      _endTime = _parseTime(savedEnd);
    }
    Future.microtask(() => ref.read(memberProvider.notifier).fetchMembers());
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
    if (_lastMemberId == null) return null;

    for (final member in members) {
      if (member.id == _lastMemberId) {
        _restoredRecentDefaults = true;
        return member;
      }
    }
    return null;
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final selectedMember = _selectedMember ?? _resolveSelectedMember(ref.read(memberProvider).members);
    if (selectedMember == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('회원을 선택하세요')),
      );
      return;
    }

    final result = await ref.read(reservationProvider.notifier).createReservation({
      'memberId': selectedMember.id,
      'date': DateFormat('yyyy-MM-dd').format(_selectedDate),
      'startTime': _formatTime(_startTime),
      'endTime': _formatTime(_endTime),
      if (_quickMemoController.text.isNotEmpty) 'quickMemo': _quickMemoController.text,
      if (_memoController.text.isNotEmpty) 'memo': _memoController.text,
    });

    if (!mounted) return;
    if (result) {
      final authBox = Hive.box(AppConstants.authBox);
      await authBox.put(AppConstants.reservationLastMemberIdKey, selectedMember.id);
      await authBox.put(AppConstants.reservationLastStartTimeKey, _formatTime(_startTime));
      await authBox.put(AppConstants.reservationLastEndTimeKey, _formatTime(_endTime));
      if (!mounted) return;
      context.pop();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('예약에 실패했습니다. 정원이 가득 찼을 수 있습니다.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final memberState = ref.watch(memberProvider);
    final selectedMember = _resolveSelectedMember(memberState.members);

    return Scaffold(
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
                subtitle: Text(DateFormat('yyyy년 M월 d일 (E)', 'ko').format(_selectedDate)),
                onTap: () async {
                  final date = await showDatePicker(
                    context: context,
                    initialDate: _selectedDate,
                    firstDate: DateTime.now().subtract(const Duration(days: 30)),
                    lastDate: DateTime.now().add(const Duration(days: 365)),
                  );
                  if (date != null) setState(() => _selectedDate = date);
                },
              ),
              const Divider(),

              // Time
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
                    child: Text('${m.name}${m.phone != null ? ' (${m.phone})' : ''}'),
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
                      Icon(Icons.history, size: 18, color: Colors.blueGrey.shade400),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '최근 예약 설정을 불러왔습니다',
                          style: TextStyle(fontSize: 12, color: Colors.blueGrey.shade600),
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

              ElevatedButton(
                onPressed: _save,
                child: const Text('예약 등록'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
