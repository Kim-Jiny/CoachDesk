DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_type
    WHERE typname = 'ReservationPolicy'
  ) THEN
    CREATE TYPE "ReservationPolicy" AS ENUM ('AUTO_CONFIRM', 'REQUEST_APPROVAL');
  END IF;
END $$;

ALTER TABLE "Organization"
ADD COLUMN IF NOT EXISTS "reservationPolicy" "ReservationPolicy" NOT NULL DEFAULT 'AUTO_CONFIRM';
