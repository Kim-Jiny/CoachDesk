CREATE TYPE "PauseRequestStatus" AS ENUM ('NONE', 'PENDING');

ALTER TABLE "MemberPackage"
ADD COLUMN "pauseStartDate" DATE,
ADD COLUMN "pauseEndDate" DATE,
ADD COLUMN "pauseRequestedStartDate" DATE,
ADD COLUMN "pauseRequestedEndDate" DATE,
ADD COLUMN "pauseRequestStatus" "PauseRequestStatus" NOT NULL DEFAULT 'NONE',
ADD COLUMN "pauseRequestReason" TEXT,
ADD COLUMN "pauseExtensionDays" INTEGER NOT NULL DEFAULT 0;
