import { Prisma } from '@prisma/client';
import { prisma } from './prisma';

type ScheduleQueryOptions = {
  organizationId: string;
  dayOfWeek?: number;
  coachId?: string;
  excludeCoachIds?: string[];
  isActive?: boolean;
  includeCoach?: boolean;
};

type OverrideQueryOptions = {
  organizationId: string;
  date?: Date;
  coachId?: string;
  startDate?: Date;
  endDate?: Date;
  includeCoach?: boolean;
};

function isMissingColumnError(err: unknown, columnName: string): boolean {
  return err instanceof Error && err.message.includes(columnName);
}

export async function findSchedulesCompat(options: ScheduleQueryOptions) {
  const {
    organizationId,
    dayOfWeek,
    coachId,
    excludeCoachIds,
    isActive,
    includeCoach = false,
  } = options;

  try {
    return await prisma.schedule.findMany({
      where: {
        organizationId,
        ...(dayOfWeek != null ? { dayOfWeek } : {}),
        ...(coachId ? { coachId } : {}),
        ...(excludeCoachIds != null && excludeCoachIds.length > 0
            ? { coachId: { notIn: excludeCoachIds } }
            : {}),
        ...(isActive != null ? { isActive } : {}),
      },
      ...(includeCoach ? { include: { coach: { select: { id: true, name: true } } } } : {}),
      orderBy: [{ dayOfWeek: 'asc' }, { startTime: 'asc' }],
    });
  } catch (err) {
    if (
      !isMissingColumnError(err, 'Schedule.breakMinutes') &&
      !isMissingColumnError(err, 'Schedule.isPublic')
    ) {
      throw err;
    }

    const conditions: Prisma.Sql[] = [Prisma.sql`s."organizationId" = ${organizationId}`];
    if (dayOfWeek != null) conditions.push(Prisma.sql`s."dayOfWeek" = ${dayOfWeek}`);
    if (coachId) conditions.push(Prisma.sql`s."coachId" = ${coachId}`);
    if (excludeCoachIds != null && excludeCoachIds.length > 0) {
      conditions.push(Prisma.sql`s."coachId" NOT IN (${Prisma.join(excludeCoachIds)})`);
    }
    if (isActive != null) conditions.push(Prisma.sql`s."isActive" = ${isActive}`);

    const rows = await prisma.$queryRaw<Array<any>>(Prisma.sql`
      SELECT
        s."id",
        s."organizationId",
        s."coachId",
        s."dayOfWeek",
        s."startTime",
        s."endTime",
        s."slotDuration",
        0 AS "breakMinutes",
        s."maxCapacity",
        false AS "isPublic",
        s."isActive",
        s."createdAt",
        s."updatedAt",
        u."id" AS "coachUserId",
        u."name" AS "coachName"
      FROM "Schedule" s
      LEFT JOIN "User" u ON u."id" = s."coachId"
      WHERE ${Prisma.join(conditions, ' AND ')}
      ORDER BY s."dayOfWeek" ASC, s."startTime" ASC
    `);

    return rows.map((row) => ({
      id: row.id,
      organizationId: row.organizationId,
      coachId: row.coachId,
      dayOfWeek: row.dayOfWeek,
      startTime: row.startTime,
      endTime: row.endTime,
      slotDuration: row.slotDuration,
      breakMinutes: 0,
      maxCapacity: row.maxCapacity,
      isPublic: row.isPublic,
      isActive: row.isActive,
      createdAt: row.createdAt,
      updatedAt: row.updatedAt,
      ...(includeCoach
          ? { coach: row.coachUserId ? { id: row.coachUserId, name: row.coachName } : null }
          : {}),
    }));
  }
}

export async function findFirstScheduleCompat(options: ScheduleQueryOptions) {
  const schedules = await findSchedulesCompat(options);
  return schedules[0] ?? null;
}

export async function findScheduleOverridesCompat(options: OverrideQueryOptions) {
  const { organizationId, date, coachId, startDate, endDate, includeCoach = false } = options;

  try {
    return await prisma.scheduleOverride.findMany({
      where: {
        organizationId,
        ...(coachId ? { coachId } : {}),
        ...(date ? { date } : {}),
        ...(startDate && endDate ? { date: { gte: startDate, lte: endDate } } : {}),
      },
      ...(includeCoach ? { include: { coach: { select: { id: true, name: true } } } } : {}),
      orderBy: { date: 'asc' },
    });
  } catch (err) {
    if (
      !isMissingColumnError(err, 'ScheduleOverride.breakMinutes') &&
      !isMissingColumnError(err, 'ScheduleOverride.isPublic')
    ) {
      throw err;
    }

    const conditions: Prisma.Sql[] = [Prisma.sql`o."organizationId" = ${organizationId}`];
    if (coachId) conditions.push(Prisma.sql`o."coachId" = ${coachId}`);
    if (date) conditions.push(Prisma.sql`o."date" = ${date}`);
    if (startDate && endDate) {
      conditions.push(Prisma.sql`o."date" >= ${startDate}`);
      conditions.push(Prisma.sql`o."date" <= ${endDate}`);
    }

    const rows = await prisma.$queryRaw<Array<any>>(Prisma.sql`
      SELECT
        o."id",
        o."organizationId",
        o."coachId",
        o."date",
        o."type",
        o."startTime",
        o."endTime",
        o."slotDuration",
        NULL::integer AS "breakMinutes",
        o."maxCapacity",
        NULL::boolean AS "isPublic",
        o."createdAt",
        u."id" AS "coachUserId",
        u."name" AS "coachName"
      FROM "ScheduleOverride" o
      LEFT JOIN "User" u ON u."id" = o."coachId"
      WHERE ${Prisma.join(conditions, ' AND ')}
      ORDER BY o."date" ASC
    `);

    return rows.map((row) => ({
      id: row.id,
      organizationId: row.organizationId,
      coachId: row.coachId,
      date: row.date,
      type: row.type,
      startTime: row.startTime,
      endTime: row.endTime,
      slotDuration: row.slotDuration,
      breakMinutes: null,
      maxCapacity: row.maxCapacity,
      isPublic: row.isPublic,
      createdAt: row.createdAt,
      ...(includeCoach
          ? { coach: row.coachUserId ? { id: row.coachUserId, name: row.coachName } : null }
          : {}),
    }));
  }
}

export async function findFirstScheduleOverrideCompat(options: OverrideQueryOptions) {
  const overrides = await findScheduleOverridesCompat(options);
  return overrides[0] ?? null;
}
