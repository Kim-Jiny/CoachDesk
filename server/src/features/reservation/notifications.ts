export function buildReservationStatusMessage(
  status: string,
  date: string,
  startTime: string,
) {
  if (status === 'PENDING') {
    return {
      title: '예약 신청',
      body: `회원이 ${date} ${startTime} 예약을 신청했습니다`,
    };
  }

  return {
    title: '새 예약',
    body: `회원이 ${date} ${startTime} 예약했습니다`,
  };
}
