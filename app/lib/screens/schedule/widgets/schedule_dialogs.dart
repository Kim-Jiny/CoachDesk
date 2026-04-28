import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme.dart';
import '../../../models/reservation.dart';
import '../../../widgets/common.dart';
import '../schedule_helpers.dart';

enum TimeAdjustmentScope { single, following }

class TimeAdjustmentSelection {
  final int deltaMinutes;
  final TimeAdjustmentScope scope;

  const TimeAdjustmentSelection({
    required this.deltaMinutes,
    required this.scope,
  });
}

Future<bool?> showTimeAdjustmentWarningsDialog(
  BuildContext context,
  List<String> warnings,
) {
  return showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('확인이 필요한 변경이에요'),
      content: Text('${warnings.join('\n\n')}\n\n그래도 시간을 조정하시겠어요?'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('취소'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: AppTheme.errorColor),
          onPressed: () => Navigator.pop(context, true),
          child: const Text('그래도 진행'),
        ),
      ],
    ),
  );
}

Future<TimeAdjustmentSelection?> showTimeAdjustDialog(
  BuildContext context, {
  required String startTime,
  required String endTime,
  required String followingLabel,
}) {
  final controller = TextEditingController(text: '10');
  var isDelay = true;
  var scope = TimeAdjustmentScope.single;
  String? errorText;

  return showDialog<TimeAdjustmentSelection>(
    context: context,
    builder: (dialogContext) {
      return StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            title: const Text('수업 시간 조절'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '현재 $startTime - $endTime',
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                ),
                const SizedBox(height: 16),
                SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(
                      value: false,
                      label: Text('앞당기기'),
                      icon: Icon(Icons.arrow_back_rounded),
                    ),
                    ButtonSegment(
                      value: true,
                      label: Text('미루기'),
                      icon: Icon(Icons.arrow_forward_rounded),
                    ),
                  ],
                  selected: {isDelay},
                  onSelectionChanged: (selection) {
                    setState(() => isDelay = selection.first);
                  },
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: controller,
                  autofocus: true,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: InputDecoration(
                    labelText: '조절할 시간 (분)',
                    hintText: '1 - 120',
                    suffixText: '분',
                    border: const OutlineInputBorder(),
                    errorText: errorText,
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  '적용 범위',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 10),
                SegmentedButton<TimeAdjustmentScope>(
                  segments: [
                    const ButtonSegment(
                      value: TimeAdjustmentScope.single,
                      label: Text('이 일정만'),
                    ),
                    ButtonSegment(
                      value: TimeAdjustmentScope.following,
                      label: Text(followingLabel),
                    ),
                  ],
                  selected: {scope},
                  onSelectionChanged: (selection) {
                    setState(() => scope = selection.first);
                  },
                ),
                const SizedBox(height: 10),
                Text(
                  scope == TimeAdjustmentScope.single
                      ? '선택한 수업 또는 빈 타임만 이동합니다'
                      : '이 시간 이후 오늘 일정이 함께 이동합니다',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade600,
                    height: 1.4,
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('취소'),
              ),
              FilledButton(
                onPressed: () {
                  final value = int.tryParse(controller.text.trim());
                  if (value == null || value <= 0 || value > 120) {
                    setState(() => errorText = '1에서 120 사이의 값을 입력해주세요');
                    return;
                  }
                  Navigator.pop(
                    dialogContext,
                    TimeAdjustmentSelection(
                      deltaMinutes: isDelay ? value : -value,
                      scope: scope,
                    ),
                  );
                },
                child: const Text('적용'),
              ),
            ],
          );
        },
      );
    },
  );
}

Future<String?> showReservationActionSheet(
  BuildContext context,
  Reservation reservation,
) {
  final canComplete = canCompleteReservation(reservation);

  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (context) {
      final reservationQuickMemo = reservation.quickMemo?.trim();
      final memberQuickMemo = reservation.memberQuickMemo?.trim();

      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 22,
                    backgroundColor: timelineStatusColor(
                      reservation.status,
                    ).withValues(alpha: 0.1),
                    child: Text(
                      reservation.memberName?[0] ?? '?',
                      style: TextStyle(
                        color: timelineStatusColor(reservation.status),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          reservation.memberName ?? '예약',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${reservation.startTime} - ${reservation.endTime}',
                          style: TextStyle(color: Colors.grey.shade600),
                        ),
                      ],
                    ),
                  ),
                  StatusBadge.fromStatus(reservation.status),
                ],
              ),
              const SizedBox(height: 16),
              _ReservationInfoRow(
                label: '상태',
                value: timelineStatusLabel(reservation.status),
              ),
              if (reservation.coachName != null &&
                  reservation.coachName!.isNotEmpty)
                _ReservationInfoRow(label: '코치', value: reservation.coachName!),
              if (memberQuickMemo != null && memberQuickMemo.isNotEmpty)
                _ReservationInfoRow(label: '회원 메모', value: memberQuickMemo),
              if (reservationQuickMemo != null &&
                  reservationQuickMemo.isNotEmpty)
                _ReservationInfoRow(
                  label: '예약 메모',
                  value: reservationQuickMemo,
                ),
              if (reservation.memo != null &&
                  reservation.memo!.trim().isNotEmpty)
                _ReservationInfoRow(
                  label: '상세 메모',
                  value: reservation.memo!.trim(),
                ),
              if (reservation.isMemberBooked)
                const _ReservationInfoRow(label: '예약 방식', value: '회원 예약'),
              if (reservation.status == 'CONFIRMED' && !canComplete)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    '수업 종료 시간 이후에만 완료 처리할 수 있습니다',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.orange.shade700,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              const SizedBox(height: 12),
              FilledButton.tonalIcon(
                onPressed: () => Navigator.pop(context, 'member'),
                icon: const Icon(Icons.person_outline_rounded),
                label: const Text('회원 상세 보기'),
              ),
              const SizedBox(height: 20),
              if (reservation.status == 'PENDING') ...[
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(
                    Icons.check_circle_outline,
                    color: AppTheme.successColor,
                  ),
                  title: const Text('예약 승인'),
                  onTap: () => Navigator.pop(context, 'approve'),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(
                    Icons.cancel_outlined,
                    color: AppTheme.errorColor,
                  ),
                  title: const Text('예약 거절'),
                  onTap: () => Navigator.pop(context, 'reject'),
                ),
              ] else if (reservation.status == 'CONFIRMED') ...[
                const SizedBox(height: 4),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(
                    Icons.cancel_outlined,
                    color: AppTheme.errorColor,
                  ),
                  title: const Text('예약 취소'),
                  subtitle: const Text('회원에게 취소 알림이 전송됩니다'),
                  onTap: () => Navigator.pop(context, 'cancel'),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(
                    Icons.edit_note_rounded,
                    color: Colors.orange,
                  ),
                  title: const Text('예약 메모 추가/수정'),
                  subtitle: const Text('짧은 메모와 상세 메모를 남길 수 있어요'),
                  onTap: () => Navigator.pop(context, 'edit_memo'),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(
                    Icons.schedule_rounded,
                    color: AppTheme.primaryColor,
                  ),
                  title: const Text('수업 시간 조절'),
                  subtitle: const Text('앞당기거나 미룰 분 수를 입력합니다'),
                  onTap: () => Navigator.pop(context, 'adjust'),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    Icons.task_alt_rounded,
                    color: canComplete
                        ? AppTheme.primaryColor
                        : Colors.grey.shade400,
                  ),
                  title: Text(
                    '수업 완료 처리',
                    style: TextStyle(
                      color: canComplete ? null : Colors.grey.shade500,
                    ),
                  ),
                  subtitle: canComplete
                      ? null
                      : const Text('아직 종료 시간이 지나지 않았습니다'),
                  enabled: canComplete,
                  onTap: canComplete
                      ? () => Navigator.pop(context, 'complete')
                      : null,
                ),
              ],
            ],
          ),
        ),
      );
    },
  );
}

Future<Reservation?> showReservationListSheet(
  BuildContext context,
  List<Reservation> reservations,
) {
  return showModalBottomSheet<Reservation>(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (context) {
      final first = reservations.first;
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${first.startTime} - ${first.endTime}',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '예약자 ${reservations.length}명',
                style: TextStyle(color: Colors.grey.shade600),
              ),
              const SizedBox(height: 16),
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: reservations.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final reservation = reservations[index];
                    final reservationQuickMemo = reservation.quickMemo?.trim();
                    final memberQuickMemo = reservation.memberQuickMemo?.trim();
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      onTap: () => Navigator.pop(context, reservation),
                      leading: CircleAvatar(
                        radius: 18,
                        backgroundColor: timelineStatusColor(
                          reservation.status,
                        ).withValues(alpha: 0.1),
                        child: Text(
                          reservation.memberName?[0] ?? '?',
                          style: TextStyle(
                            color: timelineStatusColor(reservation.status),
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      title: Text(
                        reservation.memberName ?? '이름 없음',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (memberQuickMemo != null &&
                              memberQuickMemo.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Text(
                                '회원: $memberQuickMemo',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.teal.shade700,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          if (reservationQuickMemo != null &&
                              reservationQuickMemo.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Text(
                                '예약: $reservationQuickMemo',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.orange.shade700,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          if (reservation.isMemberBooked)
                            Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Text(
                                '회원 예약',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.deepPurple.shade300,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                        ],
                      ),
                      trailing: StatusBadge.fromStatus(reservation.status),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

class _ReservationInfoRow extends StatelessWidget {
  final String label;
  final String value;

  const _ReservationInfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 72,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                color: Colors.grey.shade500,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
