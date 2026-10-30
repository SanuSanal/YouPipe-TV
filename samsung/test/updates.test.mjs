// Updates.isNewer (app/js/data/updates.js): which release counts as newer than the installed version.
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { test } from 'node:test';
import vm from 'node:vm';

const src = readFileSync(new URL('../app/js/data/updates.js', import.meta.url), 'utf8');
const ctx = {};
vm.runInNewContext(src + '\nthis.Updates = Updates;', ctx);
const { Updates } = ctx;

test('a higher MAJOR.MINOR.PATCH is newer, numerically', () => {
  assert.equal(Updates.isNewer('1.0.4', '1.0.3'), true);
  assert.equal(Updates.isNewer('1.0.10', '1.0.9'), true);
  assert.equal(Updates.isNewer('2.0.0', '1.9.9'), true);
  assert.equal(Updates.isNewer('1.0.3', '1.0.3'), false);
  assert.equal(Updates.isNewer('1.0.2', '1.0.3'), false);
});

test('a dev build is older than any release; a malformed tag is never newer', () => {
  assert.equal(Updates.isNewer('1.0.3', 'dev'), true);
  assert.equal(Updates.isNewer('beta', '1.0.3'), false);
});
