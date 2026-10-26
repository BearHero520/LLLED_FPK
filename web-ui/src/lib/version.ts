// Returns null for unknown versions so an invalid response cannot offer an upgrade.
export function compareVersions(left: string, right: string): number | null {
  const parse = (value: string) => {
    const match = value.trim().match(/^v?(\d+(?:\.\d+){1,3})(?:-([0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*))?(?:\+[0-9A-Za-z.-]+)?$/i);
    return match ? { core: match[1].split('.').map(BigInt), pre: match[2]?.split('.') } : null;
  };
  const a = parse(left), b = parse(right);
  if (!a || !b) return null;
  for (let i = 0; i < Math.max(a.core.length, b.core.length); i++) {
    const x = a.core[i] ?? 0n, y = b.core[i] ?? 0n;
    if (x !== y) return x > y ? 1 : -1;
  }
  if (!a.pre || !b.pre) return a.pre ? -1 : b.pre ? 1 : 0;
  for (let i = 0; i < Math.max(a.pre.length, b.pre.length); i++) {
    const x = a.pre[i], y = b.pre[i];
    if (x === undefined) return -1;
    if (y === undefined) return 1;
    if (x === y) continue;
    const nx = /^\d+$/.test(x), ny = /^\d+$/.test(y);
    if (nx && ny) { if (BigInt(x) !== BigInt(y)) return BigInt(x) > BigInt(y) ? 1 : -1; }
    else if (nx !== ny) return nx ? -1 : 1;
    else return x > y ? 1 : -1;
  }
  return 0;
}

export function updateState(current: string, latest?: string, reachable?: boolean) {
  if (reachable === false) return { available: false, badge: '检查失败', title: '暂时无法连接 GitHub Release' };
  if (!latest) return { available: false, badge: '尚未检查', title: '检查 GitHub Release 获取新版本' };
  const comparison = compareVersions(latest, current);
  if (comparison === null) return { available: false, badge: '无法比较版本', title: '未能识别版本号，请重新检查' };
  if (comparison > 0) return { available: true, badge: '发现新版本', title: `发现新版本 v${latest.replace(/^v/i, '')}` };
  if (comparison < 0) return { available: false, badge: '当前版本较新', title: `当前 v${current.replace(/^v/i, '')} 高于公开版本 v${latest.replace(/^v/i, '')}` };
  return { available: false, badge: '已是最新', title: `当前已是最新版本 v${current.replace(/^v/i, '')}` };
}
