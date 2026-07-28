import { Dialog } from '@base-ui/react/dialog';
import { useCallback, useEffect, useRef, useState } from 'react';
import { api } from '../lib/api';
import { boundedInt, parseIni, type IniData } from '../lib/ini';
import { ActivityPage } from './ActivityPage';
import { BiosPage } from './BiosPage';
import { DevicesPage } from './DevicesPage';
import { LabPage } from './LabPage';
import { LightingPage } from './LightingPage';
import { OverviewPage, type MappingItem, type StatusData } from './OverviewPage';

type Route = 'overview' | 'lighting' | 'activity' | 'devices' | 'bios' | 'lab';
type Toast = { message: string; type: 'ok' | 'err' } | null;
type HardwareData = Record<string, unknown>;
type BiosData = Record<string, unknown>;

const routeInfo: Record<Route, { title: string; description: string }> = {
  overview: { title: '概览', description: '查看灯控服务、实时网速与硬盘活动。' },
  lighting: { title: '灯光设置', description: '配置硬盘、网络和电源灯的状态颜色。' },
  activity: { title: '活动提示', description: '控制磁盘读写和网络流量的速度闪动。' },
  devices: { title: '设备与高级', description: '管理盘位映射、机型后端、监测频率、更新与诊断日志。' },
  bios: { title: 'BIOS 控制', description: '安全管理已支持机型的风扇、来电启动、网络唤醒与 RTC 定时开机。' },
  lab: { title: '实验室', description: '未经验证的高级硬件功能，请确认风险后谨慎使用。' },
};
const navItems: Array<{ route: Route; label: string; icon: string; warning?: string }> = [
  { route: 'overview', label: '概览', icon: 'bi-grid-1x2' }, { route: 'lighting', label: '灯光设置', icon: 'bi-lightbulb' }, { route: 'activity', label: '活动提示', icon: 'bi-activity' }, { route: 'devices', label: '设备与高级', icon: 'bi-hdd-rack' }, { route: 'bios', label: 'BIOS 控制', icon: 'bi-motherboard' }, { route: 'lab', label: '实验室', icon: 'bi-eyedropper', warning: '未经验证' },
];
const diskStates = [
  { key: 'active', color: '0 255 0', brightness: 128 }, { key: 'idle', color: '255 255 0', brightness: 64 }, { key: 'standby', color: '0 100 255', brightness: 40 }, { key: 'deep_sleep', color: '40 0 80', brightness: 24 }, { key: 'offline', color: 'off', brightness: 0 },
];
const networkStates = [
  { key: 'disconnected', color: '255 0 0', brightness: 64 }, { key: 'connected', color: '0 80 255', brightness: 48 }, { key: 'vpn', color: '160 0 255', brightness: 64 },
];
const modeLabels: Record<string, string> = { off: '关闭全部', on: '开启全部', smart: '智能模式' };

function normalizeRoute(value: string): Route { return value in routeInfo ? value as Route : 'overview'; }

function NavButton({ item, active, available, onNavigate }: { item: typeof navItems[number]; active: boolean; available: boolean; onNavigate: (route: Route) => void }) {
  return <button type="button" className={`nav-item${active ? ' active' : ''}${item.route === 'lab' ? ' lab-nav-item' : ''}`} aria-label={item.label} aria-current={active ? 'page' : undefined} hidden={!available} onClick={() => onNavigate(item.route)}><i className={`bi ${item.icon}`} aria-hidden="true" /><span>{item.label}</span>{item.warning ? <small>{item.warning}</small> : null}</button>;
}

function PageHeader({ route, running, onRefresh, refreshing }: { route: Route; running: boolean | null; onRefresh: () => void; refreshing: boolean }) {
  return <header className="page-header"><div><p className="eyebrow">NAS LIGHTING CONTROL</p><h1>{routeInfo[route].title}</h1><p className="page-description">{routeInfo[route].description}</p></div><div className="header-actions"><Dialog.Root><Dialog.Trigger className="icon-button" title="界面说明" aria-label="界面说明"><i className="bi bi-question-circle" aria-hidden="true" /></Dialog.Trigger><Dialog.Portal><Dialog.Backdrop className="newui-dialog-backdrop" /><Dialog.Popup className="newui-dialog-popup"><Dialog.Title>绿联 LED 灯控</Dialog.Title><Dialog.Description>所有页面均由离线 React 组件管理；灯光请求经 CGI API 转交内置 CLI，BIOS 请求仅转交 UGREEN-NAS-Hardware。</Dialog.Description><div className="newui-dialog-actions"><Dialog.Close className="secondary-button">知道了</Dialog.Close></div></Dialog.Popup></Dialog.Portal></Dialog.Root><button type="button" className={`icon-button${refreshing ? ' busy' : ''}`} title="刷新状态" aria-label="刷新状态" disabled={refreshing} onClick={onRefresh}><i className="bi bi-arrow-clockwise" aria-hidden="true" /></button><span className="status-pill"><span className="status-dot" /><span>{running === null ? '连接中' : running ? '服务运行中' : '后台已停止'}</span></span></div></header>;
}

function ModeDock({ mode, onModeChange }: { mode: string; onModeChange: (mode: string) => void }) {
  const modes = [['off', 'bi-power', '关闭全部'], ['on', 'bi-brightness-high', '开启全部'], ['smart', 'bi-stars', '智能模式']] as const;
  return <div className="mode-dock" aria-label="灯光模式"> <span className="dock-label">模式</span>{modes.map(([value, icon, label]) => <button key={value} type="button" className={`mode-button${value === 'smart' ? ' primary' : ''}${mode === value ? ' active' : ''}`} aria-pressed={mode === value} onClick={() => onModeChange(value)}><i className={`bi ${icon}`} aria-hidden="true" /><span>{label}</span></button>)}</div>;
}

function lightingSettingsLines(settings: IniData) {
  const lines: string[] = [];
  for (const state of diskStates) { lines.push(`disk_colors.${state.key}=${state.key === 'offline' ? 'off' : settings.disk_colors?.[state.key] || state.color}`); lines.push(`disk_brightness.${state.key}=${boundedInt(settings.disk_brightness?.[state.key], 0, 255, state.brightness)}`); }
  for (const state of networkStates) { lines.push(`netdev_colors.${state.key}=${settings.netdev_colors?.[state.key] || state.color}`); lines.push(`netdev_brightness.${state.key}=${boundedInt(settings.netdev_brightness?.[state.key], 0, 255, state.brightness)}`); }
  const power = settings.power || {};
  lines.push(`power.smart_color=${power.smart_color || '100 100 100'}`, `power.all_on_color=${power.all_on_color || '180 180 180'}`, `power.brightness=${boundedInt(power.brightness, 0, 255, 40)}`);
  return lines;
}

export function App() {
  const [route, setRoute] = useState<Route>(() => normalizeRoute(location.hash.slice(1)));
  const [status, setStatus] = useState<StatusData | null>(null);
  const [mapping, setMapping] = useState<MappingItem[]>([]);
  const [settings, setSettings] = useState<IniData>({});
  const [hardware, setHardware] = useState<HardwareData>({});
  const [bios, setBios] = useState<BiosData | null>(null);
  const [refreshing, setRefreshing] = useState(false);
  const [toast, setToast] = useState<Toast>(null);
  const toastTimer = useRef<number | undefined>(undefined);
  const showToast = useCallback((message: string, type: 'ok' | 'err' = 'ok') => { if (toastTimer.current) window.clearTimeout(toastTimer.current); setToast({ message, type }); toastTimer.current = window.setTimeout(() => setToast(null), 3200); }, []);

  const refresh = useCallback(async (notifyOnError = false) => {
    setRefreshing(true);
    try {
      const [nextStatus, nextMapping, nextHardware, nextBios] = await Promise.all([api<StatusData>('/status'), api<{ mapping?: MappingItem[] }>('/mapping'), api<HardwareData>('/hardware/status'), api<BiosData>('/bios/status')]);
      setStatus(nextStatus); setMapping(nextMapping.mapping || []); setHardware(nextHardware); setBios(nextBios);
    } catch (error) { if (notifyOnError) showToast(error instanceof Error ? error.message : '状态刷新失败', 'err'); } finally { setRefreshing(false); }
  }, [showToast]);
  const loadSettings = useCallback(async () => { const data = await api<{ raw?: string }>('/settings'); setSettings(parseIni(data.raw || '')); }, []);
  useEffect(() => { const syncRoute = () => setRoute(normalizeRoute(location.hash.slice(1))); window.addEventListener('hashchange', syncRoute); return () => window.removeEventListener('hashchange', syncRoute); }, []);
  useEffect(() => { void loadSettings().catch((error) => showToast(error instanceof Error ? error.message : '读取设置失败', 'err')); void refresh(); const interval = window.setInterval(() => { if (!document.hidden) void refresh(); }, 10000); const onVisible = () => { if (!document.hidden) void refresh(); }; document.addEventListener('visibilitychange', onVisible); return () => { window.clearInterval(interval); document.removeEventListener('visibilitychange', onVisible); }; }, [loadSettings, refresh, showToast]);
  useEffect(() => () => { if (toastTimer.current) window.clearTimeout(toastTimer.current); }, []);

  const navigate = useCallback((next: Route) => { setRoute(next); if (location.hash !== `#${next}`) location.hash = next; document.getElementById('appMain')?.scrollTo({ top: 0, behavior: 'smooth' }); }, []);
  const saveSettings = useCallback(async (lines: string[], successMessage: string) => { await api('/settings', { method: 'POST', body: lines.join('\n') }); await api('/daemon/start', { method: 'POST', body: '' }); await Promise.all([loadSettings(), refresh()]); showToast(successMessage); }, [loadSettings, refresh, showToast]);
  const setMode = useCallback(async (mode: string) => { if (!modeLabels[mode]) return; try { const data = await api<{ mode?: string }>('/mode', { method: 'POST', query: `mode=${encodeURIComponent(mode)}`, body: '' }); setStatus((current) => ({ ...current, mode: data.mode || mode })); showToast(`已切换到${modeLabels[data.mode || mode] || mode}`); await refresh(); } catch (error) { showToast(error instanceof Error ? error.message : '模式切换失败', 'err'); } }, [refresh, showToast]);
  const saveLighting = useCallback(() => saveSettings(lightingSettingsLines(settings), '灯光设置已保存'), [saveSettings, settings]);
  const applyPower26 = useCallback(async (color: string, effect: string, threshold: number, off: boolean) => { const data = await api<{ message?: string; mode?: string }>('/power26/apply', { method: 'POST', query: `color=${encodeURIComponent(color)}&effect=${encodeURIComponent(off ? 'off' : effect)}&threshold=${threshold}`, body: '' }); setStatus((current) => ({ ...current, mode: data.mode || (off ? 'off' : 'on') })); await Promise.all([loadSettings(), refresh()]); showToast(data.message || (off ? '电源灯已关闭' : '480T 电源灯设置已应用')); }, [loadSettings, refresh, showToast]);
  const power26 = hardware.profile === 'dxp480t_plus'; const running = status ? status.daemon === 'running' : null; const currentMode = status?.mode || settings.mode?.global || 'smart';

  return <div className="app-shell"><aside className="app-rail" aria-label="主导航"><div className="brand-block"><img src="./images/logo.png" alt="绿联 LED 灯控" className="brand-logo" width="48" height="48" /><div className="brand-copy"><strong>LED 灯控</strong><span>UGREEN NAS</span></div></div><nav className="rail-nav">{navItems.map((item) => <NavButton key={item.route} item={item} active={item.route === route} available={item.route !== 'bios' || Boolean(bios?.supported)} onNavigate={navigate} />)}</nav><div className="rail-footer"><span className="rail-state"><span className="status-dot" /><span>{running === null ? '正在连接' : running ? '服务运行中' : '后台已停止'}</span></span><small>v1.9.0 · <a href="https://github.com/BearHero520/LLLED_FPK" target="_blank" rel="noopener noreferrer">源代码 / AGPL-3.0</a></small></div></aside><main className="app-main" id="appMain"><PageHeader route={route} running={running} refreshing={refreshing} onRefresh={() => void refresh(true)} /><div className={`action-message${toast ? ` visible ${toast.type}` : ''}`} aria-live="polite">{toast?.message}</div><OverviewPage hidden={route !== 'overview'} status={status} mapping={mapping} onDevices={() => navigate('devices')} /><LightingPage hidden={route !== 'lighting'} settings={settings} power26={power26} onSettingsChange={setSettings} onSave={saveLighting} onPower26Apply={applyPower26} onToast={showToast} /><ActivityPage hidden={route !== 'activity'} settings={settings} onSettingsChange={setSettings} onSave={saveSettings} onToast={showToast} /><DevicesPage hidden={route !== 'devices'} mapping={mapping} hardware={hardware} settings={settings} onSettingsChange={setSettings} onSaveSettings={saveSettings} onRefresh={refresh} onToast={showToast} /><BiosPage hidden={route !== 'bios'} bios={bios} hardware={hardware} onRefresh={refresh} onToast={showToast} /><LabPage hidden={route !== 'lab'} onRefresh={refresh} onToast={showToast} /></main><ModeDock mode={currentMode} onModeChange={(mode) => void setMode(mode)} /></div>;
}
