export type IniData = Record<string, Record<string, string>>;

export function parseIni(raw: string): IniData {
  const data: IniData = {};
  let section = '';
  for (const sourceLine of String(raw || '').split('\n')) {
    const line = sourceLine.trim();
    if (!line || line.startsWith('#')) continue;
    const sectionMatch = line.match(/^\[([^\]]+)\]/);
    if (sectionMatch) {
      section = sectionMatch[1].trim();
      if (section) data[section] ??= {};
      continue;
    }
    const index = line.indexOf('=');
    if (index > 0 && section) data[section][line.slice(0, index).trim()] = line.slice(index + 1).trim();
  }
  return data;
}

export function mergeIni(base: IniData, patch: IniData): IniData {
  const result: IniData = {};
  for (const [section, values] of Object.entries(base)) result[section] = { ...values };
  for (const [section, values] of Object.entries(patch)) result[section] = { ...result[section], ...values };
  return result;
}

export function hexToRgb(hex: string): [number, number, number] {
  const match = String(hex).match(/^#?([a-f\d]{2})([a-f\d]{2})([a-f\d]{2})$/i);
  return match ? [parseInt(match[1], 16), parseInt(match[2], 16), parseInt(match[3], 16)] : [128, 128, 128];
}

export function rgbToHex(raw: string, fallback = '#808080') {
  if (raw === 'off') return '#000000';
  const values = raw.split(/\s+/).map(Number);
  if (values.length !== 3 || values.some((value) => !Number.isFinite(value))) return fallback;
  return `#${values.map((value) => Math.max(0, Math.min(255, value)).toString(16).padStart(2, '0')).join('')}`;
}

export function boundedInt(value: string | number | undefined, min: number, max: number, fallback: number) {
  const parsed = Number.parseInt(String(value), 10);
  if (!Number.isFinite(parsed)) return fallback;
  return Math.max(min, Math.min(max, parsed));
}

export function formatRate(kbps: unknown) {
  const value = Number(kbps) || 0;
  if (value >= 1024 * 1024) return `${(value / 1024 / 1024).toFixed(1)} GB/s`;
  if (value >= 1024) return `${(value / 1024).toFixed(1)} MB/s`;
  return `${Math.round(value)} KB/s`;
}
