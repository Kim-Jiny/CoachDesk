-- CreateEnum
CREATE TYPE "MemberPackageAdjustmentType" AS ENUM ('EXTEND_EXPIRY', 'SHORTEN_EXPIRY', 'ADD_SESSIONS', 'DEDUCT_SESSIONS');

-- CreateTable
CREATE TABLE "MemberPackageAdjustment" (
    "id" TEXT NOT NULL,
    "memberPackageId" TEXT NOT NULL,
    "type" "MemberPackageAdjustmentType" NOT NULL,
    "sessionDelta" INTEGER NOT NULL DEFAULT 0,
    "expiryDateBefore" TIMESTAMP(3),
    "expiryDateAfter" TIMESTAMP(3),
    "reason" TEXT,
    "adminId" TEXT NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "MemberPackageAdjustment_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE INDEX "MemberPackageAdjustment_memberPackageId_createdAt_idx" ON "MemberPackageAdjustment"("memberPackageId", "createdAt");

-- AddForeignKey
ALTER TABLE "MemberPackageAdjustment" ADD CONSTRAINT "MemberPackageAdjustment_memberPackageId_fkey" FOREIGN KEY ("memberPackageId") REFERENCES "MemberPackage"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "MemberPackageAdjustment" ADD CONSTRAINT "MemberPackageAdjustment_adminId_fkey" FOREIGN KEY ("adminId") REFERENCES "User"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
