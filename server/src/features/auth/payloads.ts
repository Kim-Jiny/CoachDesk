type MembershipUser = {
  memberships: Array<{
    role: string;
    createdAt: Date;
    organization: { id: string; name: string; inviteCode: string };
  }>;
};

export function toOrganizationsPayload(user: MembershipUser) {
  return user.memberships.map((m) => ({
    id: m.organization.id,
    name: m.organization.name,
    inviteCode: m.organization.inviteCode,
    role: m.role,
  }));
}

export function toUserPayload(user: {
  id: string;
  email: string;
  name: string;
  phone?: string | null;
  profileImage?: string | null;
}) {
  return {
    id: user.id,
    email: user.email,
    name: user.name,
    phone: user.phone,
    profileImage: user.profileImage,
  };
}

export function toMemberAccountPayload(account: {
  id: string;
  email: string;
  name: string;
}) {
  return {
    id: account.id,
    email: account.email,
    name: account.name,
  };
}

export function toMemberLinks(
  members: Array<{
    id: string;
    organizationId: string;
    name: string;
  }>,
) {
  return members.map((member) => ({
    id: member.id,
    organizationId: member.organizationId,
    name: member.name,
  }));
}
