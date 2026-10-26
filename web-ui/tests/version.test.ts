import assert from 'node:assert/strict';
import { test } from 'node:test';
import { compareVersions, updateState } from '../src/lib/version.ts';

test('3.0.0 never offers the older public 2.2.3 as an upgrade', () => {
  const state = updateState('v3.0.0', 'v2.2.3', true);
  assert.equal(state.available, false);
  assert.equal(state.badge, '当前版本较新');
  assert.match(state.title, /高于公开版本 v2.2.3/);
});
test('versions compare numerically and normalize prefixes and build metadata', () => {
  assert.equal(compareVersions('2.2.10', '2.2.9'), 1);
  assert.equal(compareVersions('v3.0.0+build.1', '3.0.0'), 0);
  assert.equal(compareVersions('3.0', '3.0.0'), 0);
  assert.equal(updateState('3.0.0', '3.0.1', true).available, true);
  assert.equal(updateState('3.0.0', '3.0.0', true).available, false);
});
test('prereleases have lower precedence than stable and compare numeric identifiers', () => {
  assert.equal(compareVersions('3.0.0-rc.2', '3.0.0-rc.10'), -1);
  assert.equal(compareVersions('3.0.0-rc.1', '3.0.0'), -1);
  assert.equal(compareVersions('3.0.0', '3.0.0-rc.1'), 1);
});
test('missing, malformed and unreachable responses cannot offer upgrades', () => {
  for (const value of ['', 'unknown', '3.invalid', '—']) {
    assert.equal(updateState('3.0.0', value, true).available, false);
    assert.equal(updateState(value, '3.0.1', true).available, false);
  }
  assert.equal(updateState('3.0.0', '4.0.0', false).available, false);
});
