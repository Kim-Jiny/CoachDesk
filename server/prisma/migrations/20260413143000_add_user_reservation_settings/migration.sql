ALTER TABLE "User"
ADD COLUMN "bookingMode" "BookingMode" NOT NULL DEFAULT 'PRIVATE',
ADD COLUMN "reservationPolicy" "ReservationPolicy" NOT NULL DEFAULT 'AUTO_CONFIRM',
ADD COLUMN "reservationNoticeText" TEXT,
ADD COLUMN "reservationNoticeImageUrl" TEXT,
ADD COLUMN "reservationOpenDaysBefore" INTEGER NOT NULL DEFAULT 30,
ADD COLUMN "reservationOpenHoursBefore" INTEGER NOT NULL DEFAULT 0,
ADD COLUMN "reservationCancelDeadlineMinutes" INTEGER NOT NULL DEFAULT 120;
