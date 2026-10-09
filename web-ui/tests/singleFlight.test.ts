import assert from 'node:assert/strict';
import { test } from 'node:test';
import { singleFlight, settledValues } from '../src/lib/singleFlight.ts';

test('simultaneous refreshes share one request and allow the next refresh', async () => {
  let calls = 0;
  let finish!: (value: number) => void;
  const refresh = singleFlight(() => { calls++; return new Promise<number>((resolve) => { finish = resolve; }); });
  const first = refresh();
  assert.equal(refresh(), first);
  await Promise.resolve();
  assert.equal(calls, 1);
  finish(42);
  assert.equal(await first, 42);
  const second = refresh();
  await Promise.resolve();
  assert.equal(calls, 2);
  finish(43);
  assert.equal(await second, 43);
});

test('an early failure keeps the flight busy until every request settles', async () => {
  let finish!: (value: string) => void;
  let calls = 0;
  const refresh = singleFlight(() => {
    calls++;
    return settledValues([Promise.reject(new Error('offline')), new Promise<string>((resolve) => { finish = resolve; })] as const);
  });
  const first = refresh();
  const rejected = assert.rejects(first, /offline/);
  await new Promise((resolve) => setTimeout(resolve, 10));
  assert.equal(refresh(), first);
  assert.equal(calls, 1);
  finish('done');
  await rejected;
  const second = refresh();
  const again = assert.rejects(second, /offline/);
  await Promise.resolve();
  assert.equal(calls, 2);
  finish('done');
  await again;
});

test('aborting a stalled refresh releases the next flight', async () => {
  const controller = new AbortController();
  let calls = 0;
  const refresh = singleFlight(() => {
    if (++calls > 1) return Promise.resolve('recovered');
    return new Promise<string>((_, reject) => {
      controller.signal.addEventListener('abort', () => reject(new Error('timeout')), { once: true });
    });
  });
  const first = refresh();
  const rejected = assert.rejects(first, /timeout/);
  await Promise.resolve();
  controller.abort();
  await rejected;
  assert.equal(await refresh(), 'recovered');
});
