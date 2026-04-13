-- CreateEnum: JoinRequestStatus
CREATE TYPE "JoinRequestStatus" AS ENUM ('PENDING', 'APPROVED', 'REJECTED');

-- CreateEnum: PlanType
CREATE TYPE "PlanType" AS ENUM ('FREE', 'BASIC', 'PRO', 'ENTERPRISE');

-- AlterEnum: OrgRole (add new values)
-- These must be outside a transaction so the values can be used immediately.
ALTER TYPE "OrgRole" ADD VALUE IF NOT EXISTS 'MANAGER';
ALTER TYPE "OrgRole" ADD VALUE IF NOT EXISTS 'STAFF';
ALTER TYPE "OrgRole" ADD VALUE IF NOT EXISTS 'VIEWER';

-- AlterTable: Organization (add plan fields)
ALTER TABLE "Organization" ADD COLUMN IF NOT EXISTS "planType" "PlanType" NOT NULL DEFAULT 'FREE';
ALTER TABLE "Organization" ADD COLUMN IF NOT EXISTS "maxAdminCount" INTEGER NOT NULL DEFAULT 2;
ALTER TABLE "Organization" ADD COLUMN IF NOT EXISTS "maxMemberCount" INTEGER NOT NULL DEFAULT 30;
ALTER TABLE "Organization" ADD COLUMN IF NOT EXISTS "planExpiresAt" TIMESTAMP(3);

-- CreateTable: CenterJoinRequest
CREATE TABLE IF NOT EXISTS "CenterJoinRequest" (
    "id" TEXT NOT NULL,
    "userId" TEXT NOT NULL,
    "organizationId" TEXT NOT NULL,
    "status" "JoinRequestStatus" NOT NULL DEFAULT 'PENDING',
    "message" TEXT,
    "reviewedBy" TEXT,
    "reviewedAt" TIMESTAMP(3),
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "CenterJoinRequest_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE INDEX IF NOT EXISTS "CenterJoinRequest_organizationId_status_idx" ON "CenterJoinRequest"("organizationId", "status");
CREATE UNIQUE INDEX IF NOT EXISTS "CenterJoinRequest_userId_organizationId_status_key" ON "CenterJoinRequest"("userId", "organizationId", "status");

-- AddForeignKey
ALTER TABLE "CenterJoinRequest" DROP CONSTRAINT IF EXISTS "CenterJoinRequest_userId_fkey";
ALTER TABLE "CenterJoinRequest" ADD CONSTRAINT "CenterJoinRequest_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "CenterJoinRequest" DROP CONSTRAINT IF EXISTS "CenterJoinRequest_organizationId_fkey";
ALTER TABLE "CenterJoinRequest" ADD CONSTRAINT "CenterJoinRequest_organizationId_fkey" FOREIGN KEY ("organizationId") REFERENCES "Organization"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- Migrate existing role data: ADMIN -> MANAGER, COACH -> STAFF
UPDATE "OrgMembership" SET "role" = 'MANAGER' WHERE "role" = 'ADMIN';
UPDATE "OrgMembership" SET "role" = 'STAFF' WHERE "role" = 'COACH';

-- Update default for OrgMembership.role
ALTER TABLE "OrgMembership" ALTER COLUMN "role" SET DEFAULT 'STAFF';
