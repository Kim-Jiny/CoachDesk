import { Prisma } from '@prisma/client';
import { prisma } from '../../utils/prisma';
import { formatDateOnly, hasKstTimePassed } from '../../utils/kst-date';

export class CompleteReservationError extends Error {
  constructor(public readonly message: string) {
    super(message);
  }
}

type CompleteReservationInput = {
  organizationId: string;
  reservationId: string;
  memberPackageId?: string;
  attendance: 'PRESENT' | 'NO_SHOW' | 'LATE' | 'CANCELLED';
  memo?: string;
  workoutRecords?: unknown;
  feedback?: string;
};

function toJsonValue(value: unknown): Prisma.InputJsonValue | undefined {
  if (value === undefined) {
    return undefined;
  }

  return value as Prisma.InputJsonValue;
}

export async function completeReservation(input: CompleteReservationInput) {
  return prisma.$transaction(async (tx) => {
    const reservation = await tx.reservation.findUnique({
      where: { id: input.reservationId },
    });

    if (!reservation || reservation.organizationId !== input.organizationId) {
      throw new CompleteReservationError('Reservation not found');
    }
    if (reservation.status !== 'CONFIRMED') {
      throw new CompleteReservationError(
        'Reservation is not in CONFIRMED status',
      );
    }
    if (!hasKstTimePassed(formatDateOnly(reservation.date), reservation.endTime)) {
      throw new CompleteReservationError(
        '수업 종료 시간 이후에만 완료 처리할 수 있습니다',
      );
    }

    if (input.memberPackageId) {
      const memberPackage = await tx.memberPackage.findUnique({
        where: { id: input.memberPackageId },
      });

      if (!memberPackage || memberPackage.status !== 'ACTIVE') {
        throw new CompleteReservationError('Invalid or inactive package');
      }
      if (memberPackage.memberId !== reservation.memberId) {
        throw new CompleteReservationError(
          'Package does not belong to this member',
        );
      }
      if (memberPackage.remainingSessions <= 0) {
        throw new CompleteReservationError('No remaining sessions in package');
      }

      const packageMember = await tx.member.findFirst({
        where: {
          id: memberPackage.memberId,
          organizationId: input.organizationId,
        },
        select: { id: true },
      });
      if (!packageMember) {
        throw new CompleteReservationError(
          'Package does not belong to this organization',
        );
      }

      await tx.memberPackage.update({
        where: { id: input.memberPackageId },
        data: {
          usedSessions: { increment: 1 },
          remainingSessions: { decrement: 1 },
          status: memberPackage.remainingSessions <= 1 ? 'EXHAUSTED' : 'ACTIVE',
        },
      });
    }

    const session = await tx.session.create({
      data: {
        organizationId: input.organizationId,
        reservationId: reservation.id,
        coachId: reservation.coachId,
        memberId: reservation.memberId,
        memberPackageId: input.memberPackageId,
        date: reservation.date,
        attendance: input.attendance,
        memo: input.memo,
        workoutRecords: toJsonValue(input.workoutRecords),
        feedback: input.feedback,
      },
    });

    await tx.reservation.update({
      where: { id: reservation.id },
      data: { status: 'COMPLETED' },
    });

    return session;
  });
}
