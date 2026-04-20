-- Migrate existing role data: ADMIN -> MANAGER, COACH -> STAFF
UPDATE "OrgMembership" SET "role" = 'MANAGER' WHERE "role" = 'ADMIN';
UPDATE "OrgMembership" SET "role" = 'STAFF' WHERE "role" = 'COACH';

-- Update default for OrgMembership.role
ALTER TABLE "OrgMembership" ALTER COLUMN "role" SET DEFAULT 'STAFF';
