-- AlterTable: Notification - make userId optional, add memberAccountId
ALTER TABLE "Notification" ALTER COLUMN "userId" DROP NOT NULL;

ALTER TABLE "Notification" ADD COLUMN IF NOT EXISTS "memberAccountId" TEXT;

-- CreateIndex
CREATE INDEX IF NOT EXISTS "Notification_memberAccountId_isRead_idx" ON "Notification"("memberAccountId", "isRead");
CREATE INDEX IF NOT EXISTS "Notification_memberAccountId_createdAt_idx" ON "Notification"("memberAccountId", "createdAt");

-- AddForeignKey
ALTER TABLE "Notification" ADD CONSTRAINT "Notification_memberAccountId_fkey" FOREIGN KEY ("memberAccountId") REFERENCES "MemberAccount"("id") ON DELETE CASCADE ON UPDATE CASCADE;
