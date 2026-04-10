CREATE TABLE "MemberGroup" (
  "id" TEXT NOT NULL,
  "organizationId" TEXT NOT NULL,
  "name" TEXT NOT NULL,
  "sortOrder" INTEGER NOT NULL DEFAULT 0,
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updatedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "MemberGroup_pkey" PRIMARY KEY ("id")
);

ALTER TABLE "Member"
ADD COLUMN "memberGroupId" TEXT,
ADD COLUMN "sortOrder" INTEGER NOT NULL DEFAULT 0;

ALTER TABLE "MemberGroup"
ADD CONSTRAINT "MemberGroup_organizationId_fkey"
FOREIGN KEY ("organizationId") REFERENCES "Organization"("id")
ON DELETE CASCADE ON UPDATE CASCADE;

ALTER TABLE "Member"
ADD CONSTRAINT "Member_memberGroupId_fkey"
FOREIGN KEY ("memberGroupId") REFERENCES "MemberGroup"("id")
ON DELETE SET NULL ON UPDATE CASCADE;

CREATE INDEX "MemberGroup_organizationId_sortOrder_idx"
ON "MemberGroup"("organizationId", "sortOrder");
