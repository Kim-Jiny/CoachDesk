import { prisma } from '../../utils/prisma';
import { encodeMemoFields } from '../../utils/memo-fields';
import { getMemberSummaryWithPackages } from './queries';

export class MemberMutationError extends Error {
  constructor(
    public readonly code:
      | 'GROUP_NOT_FOUND'
      | 'MEMBER_NOT_FOUND',
  ) {
    super(code);
  }
}

export async function createMemberGroup(params: {
  organizationId: string;
  name: string;
}) {
  const lastGroup = await prisma.memberGroup.findFirst({
    where: { organizationId: params.organizationId },
    orderBy: { sortOrder: 'desc' },
    select: { sortOrder: true },
  });

  return prisma.memberGroup.create({
    data: {
      organizationId: params.organizationId,
      name: params.name.trim(),
      sortOrder: (lastGroup?.sortOrder ?? -1) + 1,
    },
  });
}

export async function updateMemberGroup(params: {
  organizationId: string;
  groupId: string;
  name?: string;
  sortOrder?: number;
}) {
  const group = await prisma.memberGroup.updateMany({
    where: { id: params.groupId, organizationId: params.organizationId },
    data: {
      ...(params.name != null ? { name: params.name.trim() } : {}),
      ...(params.sortOrder != null ? { sortOrder: params.sortOrder } : {}),
    },
  });

  if (group.count === 0) {
    throw new MemberMutationError('GROUP_NOT_FOUND');
  }

  return prisma.memberGroup.findUnique({
    where: { id: params.groupId },
  });
}

export async function deleteMemberGroup(params: {
  organizationId: string;
  groupId: string;
}) {
  const group = await prisma.memberGroup.findFirst({
    where: { id: params.groupId, organizationId: params.organizationId },
    select: { id: true },
  });

  if (!group) {
    throw new MemberMutationError('GROUP_NOT_FOUND');
  }

  await prisma.$transaction([
    prisma.member.updateMany({
      where: { memberGroupId: group.id, organizationId: params.organizationId },
      data: { memberGroupId: null },
    }),
    prisma.memberGroup.delete({ where: { id: group.id } }),
  ]);
}

export async function createMember(params: {
  organizationId: string;
  name: string;
  phone?: string;
  email?: string;
  birthDate?: string;
  gender?: 'MALE' | 'FEMALE' | 'OTHER';
  quickMemo?: string;
  memo?: string;
}) {
  const member = await prisma.member.create({
    data: {
      organizationId: params.organizationId,
      name: params.name,
      phone: params.phone,
      email: params.email,
      birthDate: params.birthDate ? new Date(params.birthDate) : undefined,
      gender: params.gender,
      memo: encodeMemoFields({
        quickMemo: params.quickMemo,
        memo: params.memo,
      }),
    },
  });

  return member;
}

export async function updateMember(params: {
  organizationId: string;
  memberId: string;
  name?: string;
  phone?: string;
  email?: string;
  birthDate?: string;
  gender?: 'MALE' | 'FEMALE' | 'OTHER';
  quickMemo?: string;
  memo?: string;
  status?: 'ACTIVE' | 'INACTIVE' | 'ARCHIVED';
}) {
  const { birthDate, quickMemo, memo, ...rest } = params;
  const shouldUpdateMemo =
    quickMemo !== undefined || memo !== undefined;

  const member = await prisma.member.updateMany({
    where: { id: params.memberId, organizationId: params.organizationId },
    data: {
      ...rest,
      ...(shouldUpdateMemo
        ? { memo: encodeMemoFields({ quickMemo, memo }) }
        : {}),
      birthDate: birthDate ? new Date(birthDate) : undefined,
    },
  });

  if (member.count === 0) {
    throw new MemberMutationError('MEMBER_NOT_FOUND');
  }

  return getMemberSummaryWithPackages({
    organizationId: params.organizationId,
    memberId: params.memberId,
  });
}

export async function moveMemberToGroup(params: {
  organizationId: string;
  memberId: string;
  memberGroupId: string | null;
}) {
  if (params.memberGroupId != null) {
    const group = await prisma.memberGroup.findFirst({
      where: { id: params.memberGroupId, organizationId: params.organizationId },
      select: { id: true },
    });
    if (!group) {
      throw new MemberMutationError('GROUP_NOT_FOUND');
    }
  }

  const moved = await prisma.member.updateMany({
    where: { id: params.memberId, organizationId: params.organizationId },
    data: { memberGroupId: params.memberGroupId },
  });

  if (moved.count === 0) {
    throw new MemberMutationError('MEMBER_NOT_FOUND');
  }

  return getMemberSummaryWithPackages({
    organizationId: params.organizationId,
    memberId: params.memberId,
  });
}

export async function deleteMember(params: {
  organizationId: string;
  memberId: string;
}) {
  const result = await prisma.member.deleteMany({
    where: { id: params.memberId, organizationId: params.organizationId },
  });

  if (result.count === 0) {
    throw new MemberMutationError('MEMBER_NOT_FOUND');
  }
}
