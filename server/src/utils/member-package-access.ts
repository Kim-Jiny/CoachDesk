import { Prisma } from '@prisma/client';
import { prisma } from './prisma';

type ListMemberPackagesOptions = {
  memberId?: string;
  memberIds?: string[];
  organizationId?: string;
  id?: string;
};

function isMissingColumnError(err: unknown, columnName: string): boolean {
  return err instanceof Error && err.message.includes(columnName);
}

function buildConditions(options: ListMemberPackagesOptions) {
  const conditions: Prisma.Sql[] = [Prisma.sql`1 = 1`];

  if (options.id) {
    conditions.push(Prisma.sql`mp."id" = ${options.id}`);
  }
  if (options.memberId) {
    conditions.push(Prisma.sql`mp."memberId" = ${options.memberId}`);
  }
  if (options.memberIds && options.memberIds.length > 0) {
    conditions.push(Prisma.sql`mp."memberId" IN (${Prisma.join(options.memberIds)})`);
  }
  if (options.organizationId) {
    conditions.push(Prisma.sql`m."organizationId" = ${options.organizationId}`);
  }

  return conditions;
}

function mapMemberPackageRow(row: any, hasPauseColumns: boolean) {
  return {
    id: row.id,
    memberId: row.memberId,
    packageId: row.packageId,
    totalSessions: row.totalSessions,
    usedSessions: row.usedSessions,
    remainingSessions: row.remainingSessions,
    purchaseDate: row.purchaseDate,
    expiryDate: row.expiryDate,
    paidAmount: row.paidAmount,
    paymentMethod: row.paymentMethod,
    status: row.status,
    createdAt: row.createdAt,
    updatedAt: row.updatedAt,
    pauseStartDate: hasPauseColumns ? row.pauseStartDate : null,
    pauseEndDate: hasPauseColumns ? row.pauseEndDate : null,
    pauseRequestedStartDate: hasPauseColumns ? row.pauseRequestedStartDate : null,
    pauseRequestedEndDate: hasPauseColumns ? row.pauseRequestedEndDate : null,
    pauseRequestStatus: hasPauseColumns ? row.pauseRequestStatus : 'NONE',
    pauseRequestReason: hasPauseColumns ? row.pauseRequestReason : null,
    pauseExtensionDays: hasPauseColumns ? row.pauseExtensionDays ?? 0 : 0,
    package: row.packageIdValue
        ? {
            id: row.packageIdValue,
            organizationId: row.packageOrganizationId,
            name: row.packageName,
            totalSessions: row.packageTotalSessions,
            price: row.packagePrice,
            validDays: row.packageValidDays,
            isActive: row.packageIsActive,
            isPublic: row.packageIsPublic,
            createdAt: row.packageCreatedAt,
            updatedAt: row.packageUpdatedAt,
          }
        : null,
    member: row.memberIdValue
        ? {
            id: row.memberIdValue,
            name: row.memberName,
            organizationId: row.memberOrganizationId,
            memberAccountId: row.memberAccountId,
          }
        : null,
    organization: row.organizationIdValue
        ? {
            id: row.organizationIdValue,
            name: row.organizationName,
          }
        : null,
  };
}

async function queryMemberPackages(options: ListMemberPackagesOptions, hasPauseColumns: boolean) {
  const conditions = buildConditions(options);
  const pauseColumns = hasPauseColumns
    ? Prisma.sql`
        mp."pauseStartDate",
        mp."pauseEndDate",
        mp."pauseRequestedStartDate",
        mp."pauseRequestedEndDate",
        mp."pauseRequestStatus",
        mp."pauseRequestReason",
        mp."pauseExtensionDays",
      `
    : Prisma.sql`
        NULL::date AS "pauseStartDate",
        NULL::date AS "pauseEndDate",
        NULL::date AS "pauseRequestedStartDate",
        NULL::date AS "pauseRequestedEndDate",
        'NONE'::text AS "pauseRequestStatus",
        NULL::text AS "pauseRequestReason",
        0 AS "pauseExtensionDays",
      `;

  const rows = await prisma.$queryRaw<Array<any>>(Prisma.sql`
    SELECT
      mp."id",
      mp."memberId",
      mp."packageId",
      mp."totalSessions",
      mp."usedSessions",
      mp."remainingSessions",
      mp."purchaseDate",
      mp."expiryDate",
      mp."paidAmount",
      mp."paymentMethod",
      mp."status",
      mp."createdAt",
      mp."updatedAt",
      ${pauseColumns}
      p."id" AS "packageIdValue",
      p."organizationId" AS "packageOrganizationId",
      p."name" AS "packageName",
      p."totalSessions" AS "packageTotalSessions",
      p."price" AS "packagePrice",
      p."validDays" AS "packageValidDays",
      p."isActive" AS "packageIsActive",
      p."isPublic" AS "packageIsPublic",
      p."createdAt" AS "packageCreatedAt",
      p."updatedAt" AS "packageUpdatedAt",
      m."id" AS "memberIdValue",
      m."name" AS "memberName",
      m."organizationId" AS "memberOrganizationId",
      m."memberAccountId" AS "memberAccountId",
      o."id" AS "organizationIdValue",
      o."name" AS "organizationName"
    FROM "MemberPackage" mp
    INNER JOIN "Member" m ON m."id" = mp."memberId"
    INNER JOIN "Package" p ON p."id" = mp."packageId"
    INNER JOIN "Organization" o ON o."id" = m."organizationId"
    WHERE ${Prisma.join(conditions, ' AND ')}
    ORDER BY mp."createdAt" DESC
  `);

  return rows.map((row) => mapMemberPackageRow(row, hasPauseColumns));
}

export async function listMemberPackagesCompat(options: ListMemberPackagesOptions = {}) {
  try {
    return await queryMemberPackages(options, true);
  } catch (err) {
    if (
      !isMissingColumnError(err, 'MemberPackage.pauseStartDate') &&
      !isMissingColumnError(err, 'MemberPackage.pauseRequestStatus')
    ) {
      throw err;
    }
    return queryMemberPackages(options, false);
  }
}

export async function findMemberPackageCompat(options: ListMemberPackagesOptions) {
  const items = await listMemberPackagesCompat(options);
  return items[0] ?? null;
}

export async function updateMemberPackagePauseCompat(
  memberPackageId: string,
  data: {
    pauseRequestedStartDate?: Date | null;
    pauseRequestedEndDate?: Date | null;
    pauseRequestStatus?: 'NONE' | 'PENDING';
    pauseRequestReason?: string | null;
    pauseStartDate?: Date | null;
    pauseEndDate?: Date | null;
    pauseExtensionDaysDelta?: number;
    expiryDate?: Date | null;
  },
) {
  const updates: Prisma.Sql[] = [];

  if (Object.prototype.hasOwnProperty.call(data, 'pauseRequestedStartDate')) {
    updates.push(Prisma.sql`"pauseRequestedStartDate" = ${data.pauseRequestedStartDate ?? null}`);
  }
  if (Object.prototype.hasOwnProperty.call(data, 'pauseRequestedEndDate')) {
    updates.push(Prisma.sql`"pauseRequestedEndDate" = ${data.pauseRequestedEndDate ?? null}`);
  }
  if (Object.prototype.hasOwnProperty.call(data, 'pauseRequestStatus')) {
    updates.push(Prisma.sql`"pauseRequestStatus" = ${data.pauseRequestStatus ?? 'NONE'}::"PauseRequestStatus"`);
  }
  if (Object.prototype.hasOwnProperty.call(data, 'pauseRequestReason')) {
    updates.push(Prisma.sql`"pauseRequestReason" = ${data.pauseRequestReason ?? null}`);
  }
  if (Object.prototype.hasOwnProperty.call(data, 'pauseStartDate')) {
    updates.push(Prisma.sql`"pauseStartDate" = ${data.pauseStartDate ?? null}`);
  }
  if (Object.prototype.hasOwnProperty.call(data, 'pauseEndDate')) {
    updates.push(Prisma.sql`"pauseEndDate" = ${data.pauseEndDate ?? null}`);
  }
  if (Object.prototype.hasOwnProperty.call(data, 'expiryDate')) {
    updates.push(Prisma.sql`"expiryDate" = ${data.expiryDate ?? null}`);
  }
  if ((data.pauseExtensionDaysDelta ?? 0) !== 0) {
    updates.push(Prisma.sql`"pauseExtensionDays" = COALESCE("pauseExtensionDays", 0) + ${data.pauseExtensionDaysDelta ?? 0}`);
  }

  if (updates.length === 0) {
    return;
  }

  await prisma.$executeRaw(Prisma.sql`
    UPDATE "MemberPackage"
    SET ${Prisma.join([...updates, Prisma.sql`"updatedAt" = NOW()`], ', ')}
    WHERE "id" = ${memberPackageId}
  `);
}
