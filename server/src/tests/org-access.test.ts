import test from 'node:test';
import assert from 'node:assert/strict';
import { pickPrimaryMembership } from '../utils/org-access';

test('pickPrimaryMembership returns null for empty memberships', () => {
  assert.equal(pickPrimaryMembership([]), null);
});

test('pickPrimaryMembership selects the most recent membership', () => {
  const oldest = { createdAt: new Date('2026-01-01T00:00:00.000Z'), id: 'oldest' };
  const newest = { createdAt: new Date('2026-02-01T00:00:00.000Z'), id: 'newest' };

  const result = pickPrimaryMembership([newest, oldest]);

  assert.deepEqual(result, newest);
});
