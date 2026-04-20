CREATE TYPE "PackageScope" AS ENUM ('CENTER', 'ADMIN');

ALTER TABLE "Package" ADD COLUMN "coachId" TEXT;
ALTER TABLE "Package" ADD COLUMN "scope" "PackageScope" NOT NULL DEFAULT 'CENTER';

ALTER TABLE "Package"
  ADD CONSTRAINT "Package_coachId_fkey"
  FOREIGN KEY ("coachId") REFERENCES "User"("id")
  ON DELETE SET NULL ON UPDATE CASCADE;

CREATE INDEX "Package_organizationId_scope_coachId_idx" ON "Package"("organizationId", "scope", "coachId");
