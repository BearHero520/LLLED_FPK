import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { test } from 'node:test';
import { readmeHref, readmeImageSrc, readmeInlineTokens } from '../src/lib/readme.ts';

test('relative README images resolve to repository content instead of the NAS page', () => {
  for (const path of ['docs/assets/donate/alipay.jpg', './docs/assets/donate/alipay.jpg']) {
    assert.equal(readmeImageSrc(path), 'https://raw.githubusercontent.com/BearHero520/UGreen-Control/main/docs/assets/donate/alipay.jpg');
  }
  assert.equal(readmeHref('docs/releases/v3.0.6.md'), 'https://github.com/BearHero520/UGreen-Control/blob/main/docs/releases/v3.0.6.md');
});

test('published donation images become image tokens with the right repository URL', () => {
  const readme = readFileSync(new URL('../../README.md', import.meta.url), 'utf8');
  assert.doesNotMatch(readme, /<details>|<summary>|<img\s|<a\s/);
  const tokens = readmeInlineTokens(readme).filter((token) => token.kind === 'image');
  assert.equal(tokens.length, 2);
  assert.deepEqual(tokens.map((token) => token.src), [
    'https://raw.githubusercontent.com/BearHero520/UGreen-Control/main/docs/assets/donate/alipay.jpg',
    'https://raw.githubusercontent.com/BearHero520/UGreen-Control/main/docs/assets/donate/wechat.png',
  ]);
});

test('images do not consume neighboring links, bold text, or code examples', () => {
  const tokens = readmeInlineTokens('**支持** ![支付宝](docs/assets/donate/alipay.jpg) [原图](docs/assets/donate/alipay.jpg) `![示例](image.png)`');
  assert.deepEqual(tokens.filter((token) => token.kind !== 'text').map((token) => token.kind), ['strong', 'image', 'link', 'code']);
  assert.equal(tokens.at(-1)?.text, '![示例](image.png)');
});

test('unsupported image schemes remain text and raw HTML is not executed', () => {
  for (const url of ['javascript:alert', 'data:text/html,example', 'file:///tmp/image.png']) {
    assert.equal(readmeImageSrc(url), null);
    assert.deepEqual(readmeInlineTokens(`![image](${url})`), [{ kind: 'text', text: `![image](${url})` }]);
  }
  const raw = '<img src="image.png" onerror="alert(1)">';
  assert.deepEqual(readmeInlineTokens(raw), [{ kind: 'text', text: raw }]);
});
