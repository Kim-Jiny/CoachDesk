import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/api_client.dart';
import '../../models/schedule_override.dart';
import '../../widgets/common.dart';

class ScheduleSettingScreen extends ConsumerStatefulWidget {
  const ScheduleSettingScreen({super.key});

  @override
  ConsumerState<ScheduleSettingScreen> createState() =>
      _ScheduleSettingScreenState();
}

class _ScheduleSettingScreenState extends ConsumerState<ScheduleSettingScreen> {
  List<dynamic> _schedules = [];
  List<ScheduleOverride> _overrides = [];
  bool _isLoading = true;

  static const _dayNames = ['일', '월', '화', '수', '목', '금', '토'];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData({bool silent = false}) async {
    if (!silent) {
      setState(() => _isLoading = true);
    }
    try {
      final dio = ref.read(dioProvider);
      final now = DateTime.now();
      final end = now.add(const Duration(days: 90));
      final responses = await Future.wait([
        dio.get('/schedules'),
        dio.get(
          '/schedules/overrides',
          queryParameters: {
            'startDate': DateFormat('yyyy-MM-dd').format(now),
            'endDate': DateFormat('yyyy-MM-dd').format(end),
          },
        ),
      ]);
      setState(() {
        _schedules = responses[0].data as List;
        _overrides = (responses[1].data as List)
            .map(
              (json) => ScheduleOverride.fromJson(json as Map<String, dynamic>),
            )
            .toList();
        if (!silent) _isLoading = false;
      });
    } catch (_) {
      if (!silent) setState(() => _isLoading = false);
    }
  }

  Future<void> _addSchedule() async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => const _ScheduleDialog(),
    );
    if (result == null) return;

    try {
      final dio = ref.read(dioProvider);
      await dio.post('/schedules', data: result);
      _loadData(silent: true);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('추가에 실패했습니다')));
      }
    }
  }

  Future<void> _editSchedule(Map<String, dynamic> schedule) async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => _ScheduleDialog(schedule: schedule),
    );
    if (result == null) return;

    try {
      final dio = ref.read(dioProvider);
      await dio.put('/schedules/${schedule['id']}', data: result);
      _loadData(silent: true);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('수정에 실패했습니다')));
      }
    }
  }

  Future<void> _deleteSchedule(String id) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('삭제'),
        content: const Text('이 시간대를 삭제하시겠습니까?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('삭제'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final previous = List<dynamic>.from(_schedules);
    setState(() {
      _schedules.removeWhere((s) => (s as Map<String, dynamic>)['id'] == id);
    });

    try {
      final dio = ref.read(dioProvider);
      await dio.delete('/schedules/$id');
    } catch (_) {
      if (!mounted) return;
      setState(() => _schedules = previous);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('삭제에 실패했습니다')));
    }
  }

  Future<void> _addOverride() async {
    final dio = ref.read(dioProvider);
    final result = await showDialog<Object?>(
      context: context,
      builder: (context) => _OverrideDialog(dio: dio),
    );
    if (result == null) return;

    try {
      if (result is List) {
        for (final action in result) {
          final item = Map<String, dynamic>.from(action as Map);
          if (item['mode'] == 'delete') {
            await dio.delete('/schedules/overrides/${item['overrideId']}');
          } else {
            await dio.post(
              '/schedules/overrides',
              data: Map<String, dynamic>.from(
                item['data'] as Map<String, dynamic>,
              ),
            );
          }
        }
      } else {
        await dio.post(
          '/schedules/overrides',
          data: Map<String, dynamic>.from(result as Map),
        );
      }
      await _loadData(silent: true);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('예외 일정 추가에 실패했습니다')));
    }
  }

  Future<void> _deleteOverride(String id) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('예외 일정 삭제'),
        content: const Text('이 예외 일정을 삭제하시겠습니까?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('삭제'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final previous = List<ScheduleOverride>.from(_overrides);
    setState(() {
      _overrides.removeWhere((o) => o.id == id);
    });

    try {
      final dio = ref.read(dioProvider);
      await dio.delete('/schedules/overrides/$id');
    } catch (_) {
      if (!mounted) return;
      setState(() => _overrides = previous);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('예외 일정 삭제에 실패했습니다')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return DismissKeyboardOnTap(
      child: Scaffold(
        appBar: AppBar(title: const Text('수업시간 설정')),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : RefreshIndicator(
                onRefresh: _loadData,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 132),
                  children: [
                    Text(
                      '주간 가용시간',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (_schedules.isEmpty)
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Text(
                          '설정된 가용시간이 없습니다',
                          style: TextStyle(color: Colors.grey.shade500),
                        ),
                      )
                    else
                      ..._schedules.map((schedule) {
                        final s = schedule as Map<String, dynamic>;
                        final isPublic = s['isPublic'] as bool? ?? false;
                        return Card(
                          child: ListTile(
                            leading: CircleAvatar(
                              child: Text(_dayNames[s['dayOfWeek'] as int]),
                            ),
                            title: Text('${s['startTime']} - ${s['endTime']}'),
                            subtitle: Text(
                              '${s['slotDuration']}분 수업'
                              '${((s['breakMinutes'] as int?) ?? 0) > 0 ? ' · 쉬는시간 ${s['breakMinutes']}분' : ''}'
                              ' · 한 타임당 정원 ${s['maxCapacity']}명'
                              ' · ${isPublic ? '공개' : '비공개'}',
                            ),
                            trailing: IconButton(
                              icon: const Icon(
                                Icons.delete_outline,
                                color: Colors.red,
                              ),
                              onPressed: () =>
                                  _deleteSchedule(s['id'] as String),
                            ),
                            onTap: () => _editSchedule(s),
                          ),
                        );
                      }),
                    const SizedBox(height: 24),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            '예외 일정',
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.bold),
                          ),
                        ),
                        TextButton.icon(
                          onPressed: _addOverride,
                          icon: const Icon(
                            Icons.event_available_outlined,
                            size: 18,
                          ),
                          label: const Text('예외 추가'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    if (_overrides.isEmpty)
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Text(
                          '등록된 예외 일정이 없습니다',
                          style: TextStyle(color: Colors.grey.shade500),
                        ),
                      )
                    else
                      ..._overrides.map((override) {
                        final isOpen = override.type == 'OPEN';
                        final isVisibility =
                            override.type == 'VISIBLE' ||
                            override.type == 'HIDDEN';
                        final isPartialClosed =
                            override.type == 'CLOSED' &&
                            override.startTime != null &&
                            override.endTime != null;
                        return Card(
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor: isOpen
                                  ? Colors.green.shade100
                                  : isVisibility
                                  ? Colors.blue.shade100
                                  : Colors.red.shade100,
                              child: Icon(
                                isOpen
                                    ? Icons.event_available
                                    : override.type == 'VISIBLE'
                                    ? Icons.visibility_outlined
                                    : override.type == 'HIDDEN'
                                    ? Icons.visibility_off_outlined
                                    : Icons.block,
                                color: isOpen
                                    ? Colors.green.shade700
                                    : isVisibility
                                    ? Colors.blue.shade700
                                    : Colors.red.shade700,
                              ),
                            ),
                            title: Text(
                              '${DateFormat('M월 d일 (E)', 'ko').format(override.date)} ${isOpen
                                  ? '추가 오픈'
                                  : override.type == 'VISIBLE'
                                  ? '공개 전환'
                                  : override.type == 'HIDDEN'
                                  ? '비공개 전환'
                                  : isPartialClosed
                                  ? '타임 삭제'
                                  : '휴무'}',
                            ),
                            subtitle: Text(
                              isOpen
                                  ? '${override.startTime} - ${override.endTime}'
                                        ' / ${override.slotDuration ?? 60}분 수업'
                                        '${(override.breakMinutes ?? 0) > 0 ? ' / 쉬는시간 ${override.breakMinutes}분' : ''}'
                                        ' / 한 타임당 정원 ${override.maxCapacity ?? 1}명'
                                        ' / ${override.isPublic == true ? '공개' : '비공개'}'
                                  : isVisibility
                                  ? '${override.startTime} - ${override.endTime} / ${override.type == 'VISIBLE' ? '해당 시간만 공개' : '해당 시간만 비공개'}'
                                  : isPartialClosed
                                  ? '${override.startTime} - ${override.endTime} / 해당 시간만 삭제'
                                  : '해당 날짜 예약 불가',
                            ),
                            trailing: IconButton(
                              icon: const Icon(
                                Icons.delete_outline,
                                color: Colors.red,
                              ),
                              onPressed: () => _deleteOverride(override.id),
                            ),
                          ),
                        );
                      }),
                  ],
                ),
              ),
        floatingActionButton: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            FloatingActionButton.small(
              heroTag: 'override_fab',
              onPressed: _addOverride,
              child: const Icon(Icons.event_available),
            ),
            const SizedBox(height: 12),
            FloatingActionButton.extended(
              heroTag: 'schedule_fab',
              onPressed: _addSchedule,
              icon: const Icon(Icons.add),
              label: const Text('수업시간 추가'),
            ),
          ],
        ),
      ),
    );
  }
}

class _OverrideDialog extends StatefulWidget {
  final Dio dio;

  const _OverrideDialog({required this.dio});

  @override
  State<_OverrideDialog> createState() => _OverrideDialogState();
}

class _OverrideDialogState extends State<_OverrideDialog> {
  DateTime _date = DateTime.now();
  String _type = 'CLOSED';
  TimeOfDay _startTime = const TimeOfDay(hour: 9, minute: 0);
  TimeOfDay _endTime = const TimeOfDay(hour: 18, minute: 0);
  int _slotDuration = 60;
  int _breakMinutes = 0;
  int _maxCapacity = 1;
  bool _isPublic = false;
  bool _isLoadingSlots = false;
  String? _slotLoadError;
  List<Map<String, dynamic>> _visibilityCandidates = [];
  final Set<String> _selectedVisibilitySlotKeys = <String>{};

  String _fmt(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  @override
  void initState() {
    super.initState();
    _loadVisibilityCandidates();
  }

  String _slotKey(Map<String, dynamic> slot) =>
      '${slot['coachId']}|${slot['startTime']}|${slot['endTime']}';

  bool get _isVisibilityType => _type == 'VISIBLE' || _type == 'HIDDEN';

  Future<void> _loadVisibilityCandidates() async {
    if (!_isVisibilityType) {
      if (mounted) {
        setState(() {
          _isLoadingSlots = false;
          _slotLoadError = null;
          _visibilityCandidates = [];
          _selectedVisibilitySlotKeys.clear();
        });
      }
      return;
    }

    setState(() {
      _isLoadingSlots = true;
      _slotLoadError = null;
    });

    try {
      final response = await widget.dio.get(
        '/schedules/slots',
        queryParameters: {
          'date': DateFormat('yyyy-MM-dd').format(_date),
          'includePast': true,
        },
      );
      final rawSlots = (response.data as List)
          .map((item) => Map<String, dynamic>.from(item as Map))
          .toList();
      final candidates =
          rawSlots.where((slot) {
            final isPublic = slot['isPublic'] == true;
            return _type == 'VISIBLE' ? !isPublic : isPublic;
          }).toList()..sort((left, right) {
            final coachCompare = (left['coachName'] as String? ?? '').compareTo(
              right['coachName'] as String? ?? '',
            );
            if (coachCompare != 0) return coachCompare;
            final timeCompare = (left['startTime'] as String).compareTo(
              right['startTime'] as String,
            );
            if (timeCompare != 0) return timeCompare;
            return (left['endTime'] as String).compareTo(
              right['endTime'] as String,
            );
          });

      if (!mounted) return;
      setState(() {
        _isLoadingSlots = false;
        _visibilityCandidates = candidates;
        _selectedVisibilitySlotKeys
          ..clear()
          ..addAll(candidates.map(_slotKey));
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isLoadingSlots = false;
        _slotLoadError = '시간대를 불러오지 못했습니다';
        _visibilityCandidates = [];
        _selectedVisibilitySlotKeys.clear();
      });
    }
  }

  List<Map<String, dynamic>> _buildVisibilityOverrideActions() {
    final selectedSlots = _visibilityCandidates.where(
      (slot) => _selectedVisibilitySlotKeys.contains(_slotKey(slot)),
    );
    final seenDeleteOverrideIds = <String>{};

    return selectedSlots
        .map((slot) {
          final visibilityOverrideId = slot['visibilityOverrideId'] as String?;
          final baseIsPublic = slot['baseIsPublic'] == true;

          final shouldDeleteOverride =
              visibilityOverrideId != null &&
              visibilityOverrideId.isNotEmpty &&
              ((_type == 'VISIBLE' && baseIsPublic) ||
                  (_type == 'HIDDEN' && !baseIsPublic));

          if (shouldDeleteOverride) {
            if (!seenDeleteOverrideIds.add(visibilityOverrideId)) {
              return <String, dynamic>{};
            }
            return {'mode': 'delete', 'overrideId': visibilityOverrideId};
          }

          return {
            'mode': 'create',
            'data': {
              'coachId': slot['coachId'],
              'date': DateFormat('yyyy-MM-dd').format(_date),
              'type': _type,
              'startTime': slot['startTime'],
              'endTime': slot['endTime'],
            },
          };
        })
        .where((item) => item.isNotEmpty)
        .toList();
  }

  Widget _buildVisibilitySelector() {
    final actionLabel = _type == 'VISIBLE' ? '공개' : '비공개';
    final targetLabel = _type == 'VISIBLE' ? '현재 비공개 시간대' : '현재 공개 시간대';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: Text(
                '$targetLabel 목록',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            if (_visibilityCandidates.isNotEmpty)
              TextButton(
                onPressed: () {
                  setState(() {
                    if (_selectedVisibilitySlotKeys.length ==
                        _visibilityCandidates.length) {
                      _selectedVisibilitySlotKeys.clear();
                    } else {
                      _selectedVisibilitySlotKeys
                        ..clear()
                        ..addAll(_visibilityCandidates.map(_slotKey));
                    }
                  });
                },
                child: Text(
                  _selectedVisibilitySlotKeys.length ==
                          _visibilityCandidates.length
                      ? '전체 해제'
                      : '전체 선택',
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        if (_isLoadingSlots)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 20),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (_slotLoadError != null)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.red.shade50,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              _slotLoadError!,
              style: TextStyle(color: Colors.red.shade700),
            ),
          )
        else if (_visibilityCandidates.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              '$actionLabel할 시간대가 없습니다',
              style: TextStyle(color: Colors.grey.shade700),
            ),
          )
        else
          Container(
            constraints: const BoxConstraints(maxHeight: 280),
            child: SingleChildScrollView(
              child: Column(
                children: [
                  for (
                    var index = 0;
                    index < _visibilityCandidates.length;
                    index++
                  ) ...[
                    if (index > 0) const Divider(height: 1),
                    Builder(
                      builder: (context) {
                        final slot = _visibilityCandidates[index];
                        final key = _slotKey(slot);
                        final selected = _selectedVisibilitySlotKeys.contains(
                          key,
                        );
                        final coachName = slot['coachName'] as String? ?? '';
                        return CheckboxListTile(
                          value: selected,
                          contentPadding: EdgeInsets.zero,
                          controlAffinity: ListTileControlAffinity.leading,
                          title: Text(
                            '${slot['startTime']} - ${slot['endTime']}',
                          ),
                          subtitle: Text(
                            coachName.isEmpty
                                ? ((slot['isPublic'] == true)
                                      ? '현재 공개'
                                      : '현재 비공개')
                                : '$coachName 코치 · ${slot['isPublic'] == true ? '현재 공개' : '현재 비공개'}',
                          ),
                          onChanged: (value) {
                            setState(() {
                              if (value == true) {
                                _selectedVisibilitySlotKeys.add(key);
                              } else {
                                _selectedVisibilitySlotKeys.remove(key);
                              }
                            });
                          },
                        );
                      },
                    ),
                  ],
                ],
              ),
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('예외 일정 추가'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('날짜'),
              subtitle: Text(DateFormat('yyyy-MM-dd').format(_date)),
              trailing: const Icon(Icons.calendar_today_outlined, size: 18),
              onTap: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: _date,
                  firstDate: DateTime.now().subtract(const Duration(days: 30)),
                  lastDate: DateTime.now().add(const Duration(days: 365)),
                );
                if (picked != null) {
                  setState(() => _date = picked);
                  _loadVisibilityCandidates();
                }
              },
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _type,
              decoration: const InputDecoration(labelText: '예외 타입'),
              items: const [
                DropdownMenuItem(value: 'CLOSED', child: Text('휴무')),
                DropdownMenuItem(value: 'OPEN', child: Text('추가 오픈')),
                DropdownMenuItem(value: 'VISIBLE', child: Text('공개로 전환')),
                DropdownMenuItem(value: 'HIDDEN', child: Text('비공개로 전환')),
              ],
              onChanged: (value) {
                if (value != null) {
                  setState(() => _type = value);
                  _loadVisibilityCandidates();
                }
              },
            ),
            if (_type == 'OPEN') ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('시작', style: TextStyle(fontSize: 13)),
                      subtitle: Text(_fmt(_startTime)),
                      onTap: () async {
                        final t = await showTimePicker(
                          context: context,
                          initialTime: _startTime,
                        );
                        if (t != null) setState(() => _startTime = t);
                      },
                    ),
                  ),
                  Expanded(
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('종료', style: TextStyle(fontSize: 13)),
                      subtitle: Text(_fmt(_endTime)),
                      onTap: () async {
                        final t = await showTimePicker(
                          context: context,
                          initialTime: _endTime,
                        );
                        if (t != null) setState(() => _endTime = t);
                      },
                    ),
                  ),
                ],
              ),
              if (_type == 'OPEN') ...[
                const SizedBox(height: 12),
                DropdownButtonFormField<int>(
                  initialValue: _slotDuration,
                  decoration: const InputDecoration(labelText: '슬롯 시간'),
                  items: const [30, 45, 60, 90, 120]
                      .map(
                        (value) => DropdownMenuItem(
                          value: value,
                          child: Text('$value분'),
                        ),
                      )
                      .toList(),
                  onChanged: (value) =>
                      setState(() => _slotDuration = value ?? 60),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<int>(
                  initialValue: _breakMinutes,
                  decoration: const InputDecoration(labelText: '쉬는시간'),
                  items: const [0, 5, 10, 15, 20, 30]
                      .map(
                        (value) => DropdownMenuItem(
                          value: value,
                          child: Text(value == 0 ? '없음' : '$value분'),
                        ),
                      )
                      .toList(),
                  onChanged: (value) =>
                      setState(() => _breakMinutes = value ?? 0),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<int>(
                  initialValue: _maxCapacity,
                  decoration: const InputDecoration(labelText: '한 타임당 정원'),
                  items: List.generate(
                    20,
                    (i) => DropdownMenuItem(
                      value: i + 1,
                      child: Text('${i + 1}명'),
                    ),
                  ),
                  onChanged: (value) =>
                      setState(() => _maxCapacity = value ?? 1),
                ),
                const SizedBox(height: 12),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('회원 앱에 공개'),
                  subtitle: Text(
                    _isPublic
                        ? '회원이 이 추가 오픈 타임을 볼 수 있습니다'
                        : '관리자 전용 타임으로 유지됩니다',
                  ),
                  value: _isPublic,
                  onChanged: (value) => setState(() => _isPublic = value),
                ),
              ],
            ],
            if (_isVisibilityType) _buildVisibilitySelector(),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('취소'),
        ),
        FilledButton(
          onPressed: () {
            final startMinutes = _startTime.hour * 60 + _startTime.minute;
            final endMinutes = _endTime.hour * 60 + _endTime.minute;
            if (_type == 'OPEN' && startMinutes >= endMinutes) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('시작시간이 종료시간보다 빨라야 합니다')),
              );
              return;
            }

            if (_isVisibilityType) {
              if (_selectedVisibilitySlotKeys.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('변경할 시간대를 선택해주세요')),
                );
                return;
              }
              Navigator.pop(context, _buildVisibilityOverrideActions());
              return;
            }

            Navigator.pop(context, {
              'date': DateFormat('yyyy-MM-dd').format(_date),
              'type': _type,
              if (_type == 'OPEN') ...{
                'startTime': _fmt(_startTime),
                'endTime': _fmt(_endTime),
                if (_type == 'OPEN') 'slotDuration': _slotDuration,
                if (_type == 'OPEN') 'breakMinutes': _breakMinutes,
                if (_type == 'OPEN') 'maxCapacity': _maxCapacity,
                if (_type == 'OPEN') 'isPublic': _isPublic,
              },
            });
          },
          child: Text(_isVisibilityType ? '선택 적용' : '추가'),
        ),
      ],
    );
  }
}

class _ScheduleDialog extends StatefulWidget {
  final Map<String, dynamic>? schedule;

  const _ScheduleDialog({this.schedule});

  @override
  State<_ScheduleDialog> createState() => _ScheduleDialogState();
}

class _ScheduleDialogState extends State<_ScheduleDialog> {
  late int _dayOfWeek;
  late Set<int> _selectedDays;
  late TimeOfDay _startTime;
  late TimeOfDay _endTime;
  late int _slotDuration;
  late int _breakMinutes;
  late int _maxCapacity;
  late bool _isPublic;
  late final TextEditingController _slotDurationController;
  late final TextEditingController _breakMinutesController;

  bool get _isEditing => widget.schedule != null;

  static TimeOfDay _parseTime(String time) {
    final parts = time.split(':').map(int.parse).toList();
    return TimeOfDay(hour: parts[0], minute: parts[1]);
  }

  @override
  void initState() {
    super.initState();
    final s = widget.schedule;
    _dayOfWeek = s?['dayOfWeek'] as int? ?? 1;
    _selectedDays = {_dayOfWeek};
    _startTime = s != null
        ? _parseTime(s['startTime'] as String)
        : const TimeOfDay(hour: 9, minute: 0);
    _endTime = s != null
        ? _parseTime(s['endTime'] as String)
        : const TimeOfDay(hour: 18, minute: 0);
    _slotDuration = s?['slotDuration'] as int? ?? 60;
    _breakMinutes = s?['breakMinutes'] as int? ?? 0;
    _maxCapacity = s?['maxCapacity'] as int? ?? 1;
    _isPublic = s?['isPublic'] as bool? ?? false;
    _slotDurationController = TextEditingController(
      text: _slotDuration.toString(),
    );
    _breakMinutesController = TextEditingController(
      text: _breakMinutes.toString(),
    );
  }

  @override
  void dispose() {
    _slotDurationController.dispose();
    _breakMinutesController.dispose();
    super.dispose();
  }

  static const _dayNames = ['일', '월', '화', '수', '목', '금', '토'];

  String _fmt(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_isEditing ? '가용시간 수정' : '가용시간 추가'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_isEditing)
              DropdownButtonFormField<int>(
                initialValue: _dayOfWeek,
                decoration: const InputDecoration(labelText: '요일'),
                items: List.generate(
                  7,
                  (i) => DropdownMenuItem(
                    value: i,
                    child: Text('${_dayNames[i]}요일'),
                  ),
                ),
                onChanged: (v) => setState(() => _dayOfWeek = v ?? 1),
              )
            else
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      '요일',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: List.generate(7, (i) {
                      final selected = _selectedDays.contains(i);
                      return FilterChip(
                        label: Text(_dayNames[i]),
                        selected: selected,
                        onSelected: (value) {
                          setState(() {
                            if (value) {
                              _selectedDays.add(i);
                            } else if (_selectedDays.length > 1) {
                              _selectedDays.remove(i);
                            }
                          });
                        },
                      );
                    }),
                  ),
                  const SizedBox(height: 6),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      '예: 월화수 또는 월수금처럼 한 번에 설정할 수 있습니다.',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ),
                ],
              ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('시작', style: TextStyle(fontSize: 13)),
                    subtitle: Text(_fmt(_startTime)),
                    onTap: () async {
                      final t = await showTimePicker(
                        context: context,
                        initialTime: _startTime,
                      );
                      if (t != null) setState(() => _startTime = t);
                    },
                  ),
                ),
                Expanded(
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('종료', style: TextStyle(fontSize: 13)),
                    subtitle: Text(_fmt(_endTime)),
                    onTap: () async {
                      final t = await showTimePicker(
                        context: context,
                        initialTime: _endTime,
                      );
                      if (t != null) setState(() => _endTime = t);
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _slotDurationController,
              decoration: const InputDecoration(
                labelText: '수업 시간 (분)',
                hintText: '예: 60',
              ),
              keyboardType: TextInputType.number,
              onChanged: (v) {
                final parsed = int.tryParse(v);
                if (parsed != null && parsed >= 15) _slotDuration = parsed;
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _breakMinutesController,
              decoration: const InputDecoration(
                labelText: '쉬는시간 (분)',
                hintText: '예: 10',
              ),
              keyboardType: TextInputType.number,
              onChanged: (v) {
                final parsed = int.tryParse(v);
                if (parsed != null && parsed >= 0) _breakMinutes = parsed;
              },
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<int>(
              initialValue: _maxCapacity,
              decoration: const InputDecoration(labelText: '한 타임당 정원'),
              items: List.generate(
                20,
                (i) => DropdownMenuItem(value: i + 1, child: Text('${i + 1}명')),
              ),
              onChanged: (v) => setState(() => _maxCapacity = v ?? 1),
            ),
            const SizedBox(height: 12),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('회원 앱에 공개'),
              subtitle: Text(
                _isPublic ? '회원이 예약 가능한 빈 타임으로 보게 됩니다' : '관리자 화면에서만 보입니다',
              ),
              value: _isPublic,
              onChanged: (value) => setState(() => _isPublic = value),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('취소'),
        ),
        FilledButton(
          onPressed: () {
            if (!_isEditing && _selectedDays.isEmpty) {
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(const SnackBar(content: Text('요일을 하나 이상 선택해주세요')));
              return;
            }
            if (_startTime.hour * 60 + _startTime.minute >=
                _endTime.hour * 60 + _endTime.minute) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('시작시간이 종료시간보다 빨라야 합니다')),
              );
              return;
            }
            Navigator.pop(context, {
              if (_isEditing)
                'dayOfWeek': _dayOfWeek
              else
                'dayOfWeeks': _selectedDays.toList()..sort(),
              'startTime': _fmt(_startTime),
              'endTime': _fmt(_endTime),
              'slotDuration': _slotDuration,
              'breakMinutes': _breakMinutes,
              'maxCapacity': _maxCapacity,
              'isPublic': _isPublic,
            });
          },
          child: Text(_isEditing ? '저장' : '추가'),
        ),
      ],
    );
  }
}
