export const reservationRelations = {
  member: {
    select: {
      id: true,
      name: true,
      phone: true,
      memberAccountId: true,
      memo: true,
    },
  },
  coach: {
    select: {
      id: true,
      name: true,
    },
  },
} as const;

export function reservationOwnerRelations() {
  return {
    member: {
      select: {
        id: true,
        name: true,
        memberAccountId: true,
        memo: true,
      },
    },
    coach: {
      select: {
        id: true,
        name: true,
      },
    },
  } as const;
}
