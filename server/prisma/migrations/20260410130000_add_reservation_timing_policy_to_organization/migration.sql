ALTER TABLE "Organization"
ADD COLUMN "reservationOpenDaysBefore" INTEGER NOT NULL DEFAULT 30,
ADD COLUMN "reservationOpenHoursBefore" INTEGER NOT NULL DEFAULT 0,
ADD COLUMN "reservationCancelDeadlineMinutes" INTEGER NOT NULL DEFAULT 120;
