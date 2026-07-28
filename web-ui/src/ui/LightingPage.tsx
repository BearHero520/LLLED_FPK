import { useState } from 'react';
import { boundedInt, hexToRgb, mergeIni, rgbToHex, type IniData } from '../lib/ini';

type ColorSetting = { key: string; label: string; def: string; brightness: number; off?: boolean };

const diskStates: ColorSetting[] = [
  { key: 'active', label: '活动', def: '0 255 0', brightness: 128 },
  { key: 'idle', label: '空闲', def: '255 255 0', brightness: 64 },
  { key: 'standby', label: '休眠', def: '0 100 255', brightness: 40 },
  { key: 'deep_sleep', label: '深度睡眠', def: '40 0 80', brightness: 24 },
  { key: 'offline', label: '离线 / 拔出', def: 'off', brightness: 0, off: true },
];

const networkStates: ColorSetting[] = [
  { key: 'disconnected', label: '断网', def: '255 0 0', brightness: 64 },
  { key: 'connected', label: '联网', def: '0 80 255', brightness: 48 },
  { key: 'vpn', label: '外网', def: '160 0 255', brightness: 64 },
];

const presets: Record<string, { name: string; ini: IniData }> = {
  classic: { name: '经典', ini: { disk_colors: { active: '0 255 0', idle: '255 255 0', standby: '0 100 255', deep_sleep: '40 0 80', offline: 'off' }, disk_brightness: { active: '128', idle: '64', standby: '40', deep_sleep: '24', offline: '0' }, netdev_colors: { disconnected: '255 0 0', connected: '0 80 255', vpn: '160 0 255' }, netdev_brightness: { disconnected: '64', connected: '48', vpn: '64' }, power: { smart_color: '100 100 100', all_on_color: '180 180 180', brightness: '40' } } },
  minimal: { name: '极简蓝灰', ini: { disk_colors: { active: '80 160 255', idle: '60 60 80', standby: '30 50 90', deep_sleep: '20 30 50', offline: 'off' }, disk_brightness: { active: '96', idle: '32', standby: '24', deep_sleep: '16', offline: '0' }, netdev_colors: { disconnected: '80 40 40', connected: '0 120 200', vpn: '100 80 220' }, netdev_brightness: { disconnected: '48', connected: '40', vpn: '48' }, power: { smart_color: '70 75 85', all_on_color: '140 145 155', brightness: '32' } } },
  vivid: { name: '醒目警示', ini: { disk_colors: { active: '0 255 0', idle: '255 200 0', standby: '255 80 0', deep_sleep: '128 0 128', offline: 'off' }, disk_brightness: { active: '160', idle: '96', standby: '64', deep_sleep: '32', offline: '0' }, netdev_colors: { disconnected: '255 0 0', connected: '0 255 128', vpn: '255 0 255' }, netdev_brightness: { disconnected: '128', connected: '80', vpn: '96' }, power: { smart_color: '255 255 255', all_on_color: '255 220 120', brightness: '64' } } },
  soft: { name: '柔和护眼', ini: { disk_colors: { active: '100 200 120', idle: '200 180 80', standby: '100 140 180', deep_sleep: '80 60 100', offline: 'off' }, disk_brightness: { active: '64', idle: '40', standby: '28', deep_sleep: '20', offline: '0' }, netdev_colors: { disconnected: '180 80 80', connected: '80 140 180', vpn: '140 100 180' }, netdev_brightness: { disconnected: '40', connected: '36', vpn: '40' }, power: { smart_color: '90 90 95', all_on_color: '150 150 140', brightness: '28' } } },
  white: { name: '白色系', ini: { disk_colors: { active: '255 255 255', idle: '220 220 220', standby: '160 160 160', deep_sleep: '90 90 90', offline: 'off' }, disk_brightness: { active: '72', idle: '48', standby: '32', deep_sleep: '18', offline: '0' }, netdev_colors: { disconnected: '120 120 120', connected: '255 255 255', vpn: '255 255 255' }, netdev_brightness: { disconnected: '32', connected: '48', vpn: '64' }, power: { smart_color: '200 200 200', all_on_color: '255 255 255', brightness: '40' } } },
};

function ColorGrid({ items, colorSection, brightnessSection, settings, onChange }: {
  items: ColorSetting[];
  colorSection: string;
  brightnessSection: string;
  settings: IniData;
  onChange: (next: IniData) => void;
}) {
  const update = (key: string, color?: string, brightness?: number) => {
    const next = mergeIni(settings, {
      [colorSection]: color === undefined ? {} : { [key]: color },
      [brightnessSection]: brightness === undefined ? {} : { [key]: String(brightness) },
    });
    onChange(next);
  };
  return <div className="color-grid">
    {items.map((item) => {
      if (item.off) return <div className="color-row" key={item.key}><label>{item.label}</label><span className="off-tag">自动关灯</span></div>;
      const rawColor = settings[colorSection]?.[item.key] || item.def;
      const brightness = boundedInt(settings[brightnessSection]?.[item.key], 0, 255, item.brightness);
      return <div className="color-row" key={item.key}>
        <label>{item.label}</label>
        <input type="color" value={rgbToHex(rawColor)} aria-label={`${item.label}颜色`} onChange={(event) => {
          const [red, green, blue] = hexToRgb(event.target.value);
          update(item.key, `${red} ${green} ${blue}`);
        }} />
        <input className="brightness-input" type="range" min="0" max="255" step="1" value={brightness} aria-label={`${item.label}亮度`} onChange={(event) => update(item.key, undefined, boundedInt(event.target.value, 0, 255, item.brightness))} />
        <output className="brightness-value">{brightness}</output>
      </div>;
    })}
  </div>;
}

function StandardLighting({ settings, onChange, onSave, onToast }: {
  settings: IniData;
  onChange: (next: IniData) => void;
  onSave: () => Promise<void>;
  onToast: (message: string, type?: 'ok' | 'err') => void;
}) {
  const [panel, setPanel] = useState<'disk' | 'network' | 'power'>('disk');
  const [saving, setSaving] = useState(false);
  const save = async () => {
    setSaving(true);
    try { await onSave(); } catch { /* The caller has already rendered the actionable error. */ } finally { setSaving(false); }
  };
  const setPowerColor = (key: 'smart_color' | 'all_on_color', value: string) => {
    const [red, green, blue] = hexToRgb(value);
    onChange(mergeIni(settings, { power: { [key]: `${red} ${green} ${blue}` } }));
  };
  const powerBrightness = boundedInt(settings.power?.brightness, 0, 255, 40);

  return <>
    <div className="settings-tabs glass-surface" role="tablist" aria-label="灯光设置分类">
      {([['disk', 'bi-device-hdd', '硬盘灯'], ['network', 'bi-wifi', '网络灯'], ['power', 'bi-power', '电源灯']] as const).map(([key, icon, label]) => (
        <button key={key} type="button" className={`settings-tab${panel === key ? ' active' : ''}`} role="tab" aria-selected={panel === key} onClick={() => setPanel(key)}><i className={`bi ${icon}`} aria-hidden="true" /><span>{label}</span></button>
      ))}
    </div>
    <div className="settings-layout">
      <article className="glass-surface settings-surface" hidden={panel !== 'disk'}>
        <div className="section-heading"><div><span className="section-kicker">DISK LED</span><h2>硬盘状态颜色</h2></div><span className="soft-badge">智能模式</span></div>
        <p className="surface-help">为活动、空闲、休眠和离线状态设置颜色与亮度。</p>
        <ColorGrid items={diskStates} colorSection="disk_colors" brightnessSection="disk_brightness" settings={settings} onChange={onChange} />
      </article>
      <article className="glass-surface settings-surface" hidden={panel !== 'network'}>
        <div className="section-heading"><div><span className="section-kicker">NETWORK LED</span><h2>网络状态颜色</h2></div></div>
        <p className="surface-help">外网、联网和断网状态分别使用独立颜色。</p>
        <ColorGrid items={networkStates} colorSection="netdev_colors" brightnessSection="netdev_brightness" settings={settings} onChange={onChange} />
      </article>
      <article className="glass-surface settings-surface" hidden={panel !== 'power'}>
        <div className="section-heading"><div><span className="section-kicker">POWER LED</span><h2>电源灯</h2></div></div>
        <p className="surface-help">设置智能模式和全部开启时的电源灯表现。</p>
        <div className="color-grid">
          <div className="color-row is-color-only"><label>智能模式</label><input type="color" value={rgbToHex(settings.power?.smart_color || '100 100 100')} aria-label="智能模式颜色" onChange={(event) => setPowerColor('smart_color', event.target.value)} /></div>
          <div className="color-row is-color-only"><label>全部开启</label><input type="color" value={rgbToHex(settings.power?.all_on_color || '180 180 180')} aria-label="全部开启颜色" onChange={(event) => setPowerColor('all_on_color', event.target.value)} /></div>
          <div className="color-row is-brightness-only"><label>亮度</label><input className="brightness-input" type="range" min="0" max="255" step="1" value={powerBrightness} aria-label="电源灯亮度" onChange={(event) => onChange(mergeIni(settings, { power: { brightness: String(boundedInt(event.target.value, 0, 255, 40)) } }))} /><output className="brightness-value">{powerBrightness}</output></div>
        </div>
      </article>
      <article className="glass-surface preset-surface">
        <div><span className="section-kicker">PRESETS</span><h2>配色方案</h2><p className="surface-help">套用方案后仍可继续微调。</p></div>
        <div className="preset-list">
          {Object.entries(presets).map(([key, preset]) => <button key={key} type="button" className="preset-button" onClick={() => { onChange(mergeIni(settings, preset.ini)); onToast(`已套用“${preset.name}”，保存后生效`); }}>{preset.name}</button>)}
        </div>
      </article>
    </div>
    <div className="view-actions"><button type="button" className="primary-button" disabled={saving} aria-busy={saving} onClick={() => void save()}><i className="bi bi-floppy" aria-hidden="true" />{saving ? '正在保存…' : '保存灯光设置'}</button></div>
  </>;
}

function Power26Lighting({ settings, onApply }: { settings: IniData; onApply: (color: string, effect: string, threshold: number, off: boolean) => Promise<void> }) {
  const [color, setColor] = useState(settings.power26?.color === 'red' ? 'red' : 'white');
  const [effect, setEffect] = useState(['steady', 'fast', 'slow', 'breath', 'network'].includes(settings.power26?.effect || '') ? settings.power26?.effect || 'steady' : 'steady');
  const [threshold, setThreshold] = useState(boundedInt(settings.power26?.network_threshold_kbps, 1, 1048576, 32));
  const [busy, setBusy] = useState(false);
  const apply = async (off: boolean) => {
    setBusy(true);
    try { await onApply(color, effect, threshold, off); } finally { setBusy(false); }
  };
  const colorLabel = color === 'red' ? '红色' : '白色';
  const effectLabel: Record<string, string> = { steady: '常亮', fast: '快闪', slow: '慢闪', breath: '呼吸', network: '网络活动' };
  return <div className="power26-layout">
    <article className="glass-surface power26-control-surface">
      <div className="section-heading"><div><span className="section-kicker">DXP480T POWER LED</span><h2>电源灯控制</h2></div><span className="soft-badge">专用 N76E003 控制器</span></div>
      <p className="surface-help">选择电源灯颜色和灯效，应用后立即生效，并由后台服务保持当前设置。</p>
      <div className="power26-controller">
        <div className="power26-preview"><span className="power26-lamp" data-color={color} data-effect={effect} /><div><small>效果预览</small><strong>{colorLabel} · {effectLabel[effect]}</strong></div></div>
        <fieldset className="power26-option-group"><legend>颜色</legend><div className="power26-color-options">
          {([['white', 'white', '白色', '日常状态'], ['red', 'red', '红色', '警示状态']] as const).map(([value, swatch, label, detail]) => <label key={value} className="power26-choice color-choice"><input type="radio" name="reactPower26Color" value={value} checked={color === value} onChange={() => setColor(value)} /><span className={`power26-choice-swatch ${swatch}`} aria-hidden="true" /><span><strong>{label}</strong><small>{detail}</small></span></label>)}
        </div></fieldset>
        <fieldset className="power26-option-group"><legend>灯效</legend><div className="power26-effect-options">
          {([['steady', 'bi-brightness-high', '常亮', '持续点亮'], ['fast', 'bi-lightning-charge', '快闪', '快速闪烁'], ['slow', 'bi-clock', '慢闪', '缓慢闪烁'], ['breath', 'bi-wind', '呼吸', '明暗呼吸'], ['network', 'bi-activity', '网络活动', '按网速闪动']] as const).map(([value, icon, label, detail]) => <label key={value} className="power26-choice effect-choice"><input type="radio" name="reactPower26Effect" value={value} checked={effect === value} onChange={() => setEffect(value)} /><i className={`bi ${icon}`} aria-hidden="true" /><span><strong>{label}</strong><small>{detail}</small></span></label>)}
        </div></fieldset>
        <div className="power26-network-options" hidden={effect !== 'network'}><div><strong>网络闪动阈值</strong><small>总上传与下载速度超过此值后，电源灯开始闪动。</small></div><label><input type="number" min="1" max="1048576" step="1" value={threshold} onChange={(event) => setThreshold(boundedInt(event.target.value, 1, 1048576, 32))} /><span>KB/s</span></label></div>
      </div>
      <div className="power26-actions"><button type="button" className="secondary-button" disabled={busy} onClick={() => void apply(true)}><i className="bi bi-power" aria-hidden="true" />关闭灯光</button><button type="button" className="primary-button" disabled={busy} onClick={() => void apply(false)}><i className="bi bi-check2-circle" aria-hidden="true" />{busy ? '正在应用…' : '应用灯光'}</button></div>
    </article>
    <aside className="glass-surface power26-info-surface"><span className="surface-icon blue"><i className="bi bi-info-circle" aria-hidden="true" /></span><div><span className="section-kicker">480T ONLY</span><h2>当前机型专用页面</h2></div><p className="surface-help">此页面只会在 DXP480T / Plus 使用专用后端时显示，其他机型仍使用完整 RGB 灯控页面。</p><div className="power26-facts"><span><small>I²C 总线</small><strong>自动探测</strong></span><span><small>控制地址</small><strong>0x31 / 0x26</strong></span><span><small>可用颜色</small><strong>红色 / 白色</strong></span><span><small>亮度调节</small><strong>不支持</strong></span></div></aside>
  </div>;
}

export function LightingPage({ hidden, settings, power26, onSettingsChange, onSave, onPower26Apply, onToast }: {
  hidden: boolean;
  settings: IniData;
  power26: boolean;
  onSettingsChange: (next: IniData) => void;
  onSave: () => Promise<void>;
  onPower26Apply: (color: string, effect: string, threshold: number, off: boolean) => Promise<void>;
  onToast: (message: string, type?: 'ok' | 'err') => void;
}) {
  return <section className="react-view" hidden={hidden} aria-label="灯光设置">
    {power26 ? <Power26Lighting settings={settings} onApply={onPower26Apply} /> : <StandardLighting settings={settings} onChange={onSettingsChange} onSave={onSave} onToast={onToast} />}
  </section>;
}
