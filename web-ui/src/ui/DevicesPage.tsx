import { useCallback, useEffect, useState } from 'react';
import { api } from '../lib/api';
import { boundedInt, formatRate, mergeIni, type IniData } from '../lib/ini';
import type { MappingItem } from './OverviewPage';

type HardwareData = Record<string, unknown>;
type LogData = { content?: string; write_level?: string; requested_lines?: number; size_bytes?: number; updated_at?: number; clipped?: boolean };
type Toast = (message: string, type?: 'ok' | 'err') => void;

const profiles = [
  ['auto', '自动识别'], ['dx4600', 'UGREEN DX4600 Pro'], ['dx4700', 'UGREEN DX4700+'], ['dxp2800', 'UGREEN DXP2800'], ['dxp2800_gt', 'UGREEN DXP2800 GT（待验证）'], ['dxp4800', 'UGREEN DXP4800'], ['dxp4800_plus', 'UGREEN DXP4800 Plus'], ['dxp4800_pro', 'UGREEN DXP4800 Pro（待验证）'], ['dxp4800s', 'UGREEN DXP4800S（BIOS 控制固件逆向）'], ['dxp4800_gt', 'UGREEN DXP4800 GT（实验性）'], ['dxp6800', 'UGREEN DXP6800 Pro'], ['dxp8800', 'UGREEN DXP8800 Plus'], ['dxp480t_plus', 'UGREEN DXP480T / Plus（仅电源灯）'], ['idx6011', 'UGREEN iDX6011（实验性）'], ['idx6011_pro', 'UGREEN iDX6011 Pro（实验性）'],
] as const;
const diskLabels: Record<string, string> = { active: '活动', idle: '空闲', standby: '休眠', deep_sleep: '深度睡眠', offline: '离线', unknown: '未知', error: '异常', '?': '未知' };
const supportLabels: Record<string, string> = { stable: '已验证', experimental: '实验性', unverified: '待验证', limited: '受限支持', unsupported: '暂不支持', unknown: '未知机型' };

function downloadText(content: string, filename: string) {
  const blob = new Blob([content], { type: 'text/plain;charset=utf-8' });
  const url = URL.createObjectURL(blob);
  const link = document.createElement('a');
  link.href = url; link.download = filename; document.body.append(link); link.click(); link.remove(); URL.revokeObjectURL(url);
}

function bytes(value: unknown) {
  const size = Math.max(0, Number(value) || 0);
  if (size >= 1024 * 1024) return `${(size / 1024 / 1024).toFixed(2)} MiB`;
  if (size >= 1024) return `${(size / 1024).toFixed(1)} KiB`;
  return `${size} B`;
}

function StateChip({ state }: { state?: string }) {
  const value = String(state || 'unknown').trim();
  return <span className={`state-chip ${value || 'unknown'}`}>{diskLabels[value] || value || '未知'}</span>;
}

export function DevicesPage({
  hidden, mapping, hardware, settings, onSettingsChange, onSaveSettings, onRefresh, onToast,
}: {
  hidden: boolean;
  mapping: MappingItem[];
  hardware: HardwareData;
  settings: IniData;
  onSettingsChange: (settings: IniData) => void;
  onSaveSettings: (lines: string[], successMessage: string) => Promise<void>;
  onRefresh: () => Promise<void>;
  onToast: Toast;
}) {
  const [logs, setLogs] = useState<LogData | null>(null);
  const [filter, setFilter] = useState('all');
  const [lineCount, setLineCount] = useState('500');
  const [writeLevel, setWriteLevel] = useState('info');
  const [busy, setBusy] = useState<string | null>(null);
  const settingsHardware = settings.hardware || {};
  const profile = settingsHardware.profile || 'auto';
  const backend = settingsHardware.backend || 'cli';
  const protocol = settingsHardware.write_protocol || 'auto';
  const probeInterval = boundedInt(settings.daemon?.disk_power_probe_interval, 10, 3600, 60);
  const hotplugInterval = boundedInt(settings.daemon?.hotplug_check_interval, 5, 3600, 30);

  const loadLogs = useCallback(async () => {
    const data = await api<LogData>(`/logs`, { query: `source=application&level=${encodeURIComponent(filter)}&lines=${encodeURIComponent(lineCount)}` });
    setLogs(data); setWriteLevel(String(data.write_level || 'info'));
  }, [filter, lineCount]);
  useEffect(() => { if (!hidden) void loadLogs().catch(() => {}); }, [hidden, loadLogs]);

  const withBusy = async (name: string, action: () => Promise<void>) => {
    setBusy(name);
    try { await action(); } catch (error) { onToast(error instanceof Error ? error.message : '操作失败', 'err'); } finally { setBusy(null); }
  };
  const updateSettings = (section: string, patch: Record<string, string>) => onSettingsChange(mergeIni(settings, { [section]: patch }));
  const saveHardware = async () => {
    if (backend === 'cli' && Boolean(hardware.driver_loaded)) { onToast('内核驱动仍在占用 MCU，请先卸载驱动并切回 CLI', 'err'); return; }
    await onSaveSettings([`hardware.backend=${backend}`, `hardware.profile=${profile}`, `hardware.write_protocol=${protocol}`], '硬件设置已保存');
  };
  const currentBackend = hardware.backend_active === 'sysfs' ? '内核驱动 / sysfs' : hardware.backend_active === 'power-0x26' ? 'N76E003 电源灯控制' : hardware.backend_active === 'cli' ? '内置 CLI' : '不可用';
  const hardwareMessage = [
    hardware.led_plugin_conflict ? `检测到可能占用 LED 控制器的模块：${hardware.led_plugin_modules || '未知模块'}。请停用后重启灯光服务。` : '',
    hardware.driver_conflict ? '检测到厂商 LED 内核模块，可能与内置 CLI 争用控制器。' : '',
    ['experimental', 'unverified'].includes(String(hardware.support)) ? '该机型需要实机验证，请先在实验室逐灯确认。' : '',
  ].filter(Boolean).join(' ');

  return <section className="react-view" hidden={hidden} aria-label="设备与高级">
    <div className="device-layout">
      <article className="glass-surface device-map-surface"><div className="section-heading"><div><span className="section-kicker">HCTL MAPPING</span><h2>硬盘与 LED 映射</h2></div><button type="button" className="secondary-button" disabled={busy === 'remap'} onClick={() => void withBusy('remap', async () => { const result = await api<{ message?: string }>('/remap', { method: 'POST', body: '' }); onToast(result.message || '硬盘映射已更新'); await onRefresh(); })}><i className="bi bi-arrow-repeat" aria-hidden="true" />重新检测</button></div><div className="table-scroll"><table className="data-table"><thead><tr><th>设备</th><th>LED</th><th>状态</th><th>读取</th><th>写入</th></tr></thead><tbody>{mapping.length ? mapping.map((item, index) => <tr key={`${item.device || 'disk'}-${index}`}><td>{item.device || '—'}</td><td>{item.led || '—'}</td><td><StateChip state={item.state} /></td><td>{formatRate(item.read_kbps)}</td><td>{formatRate(item.write_kbps)}</td></tr>) : <tr><td colSpan={5} className="empty-row">暂未检测到硬盘映射</td></tr>}</tbody></table></div></article>

      <article className="glass-surface hardware-surface"><div className="section-heading"><div><span className="section-kicker">HARDWARE BACKEND</span><h2>机型与控制后端</h2><p className="surface-help">确认当前机型识别结果与 LED 控制路径；大多数情况下保持自动识别即可。</p></div><span className="soft-badge">{supportLabels[String(hardware.support)] || String(hardware.support || '检测中')}</span></div><div className="hardware-identity-strip">
        <div className="hardware-identity-item"><i className="bi bi-pc-display-horizontal" aria-hidden="true" /><span><small>DMI 机型</small><strong title={String(hardware.product_name || '未读取到')}>{String(hardware.product_name || '未读取到')}</strong></span></div>
        <div className="hardware-identity-item"><i className="bi bi-grid-3x3-gap" aria-hidden="true" /><span><small>识别档案</small><strong>{String(hardware.profile_name || hardware.profile || '未知')}</strong></span></div>
        <div className="hardware-identity-item"><i className="bi bi-terminal" aria-hidden="true" /><span><small>CLI 版本</small><strong>{String(hardware.cli_version || '未知')}</strong></span></div>
        <div className="hardware-identity-item"><i className="bi bi-diagram-3" aria-hidden="true" /><span><small>当前路径</small><strong>{currentBackend}</strong></span></div>
      </div><div className="hardware-fields">
        <label className="hardware-field"><span><strong>机型档案</strong><small>决定灯位数量、编号和硬盘 HCTL 映射；通常保持自动识别</small></span><select className="hardware-select" value={profile} onChange={(event) => updateSettings('hardware', { profile: event.target.value })}>{profiles.map(([value, label]) => <option key={value} value={value}>{label}</option>)}</select></label>
        <label className="hardware-field"><span><strong>控制后端</strong><small>推荐保持自动或使用内置 CLI</small></span><select className="hardware-select" value={backend} onChange={(event) => updateSettings('hardware', { backend: event.target.value })}><option value="auto">自动选择（推荐）</option><option value="cli">内置 CLI</option></select></label>
        <label className="hardware-field"><span><strong>写入协议</strong><small>I²C 数据包格式，通常保持自动选择</small></span><select className="hardware-select" value={protocol} onChange={(event) => updateSettings('hardware', { write_protocol: event.target.value })}><option value="auto">自动选择（推荐）</option><option value="legacy">legacy</option><option value="smbus-block">smbus-block（实验性）</option></select></label>
      </div><div className="hardware-facts"><span><small>写入协议</small><strong>{String(hardware.write_protocol || '自动')}</strong></span><span><small>灯位布局</small><strong>{Number(hardware.netdev_count || 1)} 网络灯 · {Number(hardware.disk_count || 0)} 硬盘灯</strong></span><span><small>系统内核</small><strong>{String(hardware.kernel || '未知')}</strong></span><span><small>控制范围</small><strong>{hardware.backend_active === 'power-0x26' ? '红 / 白电源灯' : '电源、网络与硬盘灯'}</strong></span></div>{hardwareMessage ? <div className="hardware-message" role="status">{hardwareMessage}</div> : null}<div className="hardware-path-note"><i className="bi bi-shield-check" aria-hidden="true" /><span>所有 LED 写入统一交给应用内置 <strong>ugreen_leds_cli</strong>；这里仅保存机型档案与协议偏好，不直接访问 I²C 或硬件寄存器。</span></div><details className="hardware-guide"><summary className="hardware-guide-summary"><span className="hardware-guide-title"><i className="bi bi-info-circle" aria-hidden="true" /><span><strong>查看控制路径说明</strong><small>内置 CLI 与 DXP480T 专用能力</small></span></span><i className="bi bi-chevron-down" aria-hidden="true" /></summary><div className="hardware-guide-body"><div className="hardware-guide-grid"><div className={`hardware-guide-item${hardware.backend_active === 'cli' ? ' is-active' : ''}`}><div className="hardware-guide-item-head"><span><i className="bi bi-terminal" aria-hidden="true" /><strong>内置 CLI</strong></span></div><p>应用唯一的 LED 写入入口，负责普通机型的电源灯、网络灯和硬盘灯。</p></div><div className={`hardware-guide-item${hardware.backend_active === 'power-0x26' ? ' is-active' : ''}`}><div className="hardware-guide-item-head"><span><i className="bi bi-lightbulb" aria-hidden="true" /><strong>DXP480T 专用能力</strong></span></div><p>通过同一内置 CLI 控制红 / 白电源灯，不提供硬盘灯与网络灯。</p></div></div></div></details><div className="hardware-actions"><button type="button" className="primary-button" disabled={busy === 'hardware'} onClick={() => void withBusy('hardware', saveHardware)}><i className="bi bi-floppy" aria-hidden="true" />保存硬件设置</button></div></article>

      <article className="glass-surface monitoring-surface"><div className="section-heading"><div><span className="section-kicker">LOW WAKE</span><h2>监测频率</h2></div><span className="soft-badge">单位：秒</span></div><p className="surface-help">数值越低，状态更新越快，但可能增加硬盘或控制器被查询的频率。</p><div className="monitoring-fields"><label className="threshold-field"><span className="monitoring-field-copy"><strong>硬盘电源状态</strong><small>建议 60 秒，可设置 10–3600 秒</small></span><span className="number-wrap"><input type="number" min="10" max="3600" value={probeInterval} onChange={(event) => updateSettings('daemon', { disk_power_probe_interval: String(boundedInt(event.target.value, 10, 3600, 60)) })} /><em>秒</em></span></label><label className="threshold-field"><span className="monitoring-field-copy"><strong>热插拔扫描</strong><small>建议 30 秒，可设置 5–3600 秒</small></span><span className="number-wrap"><input type="number" min="5" max="3600" value={hotplugInterval} onChange={(event) => updateSettings('daemon', { hotplug_check_interval: String(boundedInt(event.target.value, 5, 3600, 30)) })} /><em>秒</em></span></label></div><div className="monitoring-actions"><button type="button" className="primary-button" disabled={busy === 'monitor'} onClick={() => void withBusy('monitor', async () => onSaveSettings([`daemon.disk_power_probe_interval=${probeInterval}`, `daemon.hotplug_check_interval=${hotplugInterval}`], '监测频率已保存'))}><i className="bi bi-floppy" aria-hidden="true" />保存监测频率</button></div></article>

      <article className="glass-surface log-surface"><div className="section-heading log-heading"><div><span className="section-kicker">TROUBLESHOOTING LOG</span><h2>应用诊断日志</h2><p className="surface-help">包含组件、事件、PID、请求 ID、来源与错误上下文；自动脱敏、截断并轮转。</p></div><span className="soft-badge">{String(logs?.write_level || 'info').toUpperCase()} · {logs?.requested_lines || lineCount} 行上限</span></div><div className="log-toolbar"><label><span>查看级别</span><select className="hardware-select" value={filter} onChange={(event) => setFilter(event.target.value)}><option value="all">全部</option><option value="error">仅 ERROR</option><option value="warn">仅 WARN</option><option value="info">仅 INFO</option><option value="debug">仅 DEBUG</option></select></label><label><span>最近行数</span><select className="hardware-select" value={lineCount} onChange={(event) => setLineCount(event.target.value)}><option value="200">200 行</option><option value="500">500 行</option><option value="1000">1000 行</option></select></label><label><span>记录级别</span><select className="hardware-select" value={writeLevel} onChange={(event) => setWriteLevel(event.target.value)}><option value="info">INFO（日常）</option><option value="debug">DEBUG（详细排错）</option><option value="warn">WARN</option><option value="error">ERROR</option></select></label><button type="button" className="secondary-button" disabled={busy === 'log-level'} onClick={() => void withBusy('log-level', async () => { const result = await api<{ message?: string }>('/logs/config', { method: 'POST', query: `level=${encodeURIComponent(writeLevel)}`, body: '' }); onToast(result.message || `日志级别已切换为 ${writeLevel.toUpperCase()}`); await loadLogs(); })}><i className="bi bi-sliders" aria-hidden="true" />应用级别</button><button type="button" className="secondary-button" disabled={busy === 'logs'} onClick={() => void withBusy('logs', loadLogs)}><i className="bi bi-arrow-clockwise" aria-hidden="true" />刷新</button><button type="button" className="secondary-button" onClick={() => { if (!logs?.content) { onToast('当前没有可复制的日志', 'err'); return; } void navigator.clipboard?.writeText(logs.content).then(() => onToast('日志已复制到剪贴板')).catch(() => onToast('复制日志失败', 'err')); }}><i className="bi bi-clipboard" aria-hidden="true" />复制</button><button type="button" className="secondary-button" onClick={() => { if (!logs?.content) { onToast('当前没有可下载的日志', 'err'); return; } downloadText(`${logs.content}\n`, `ugreen-led-application-${new Date().toISOString().replace(/[:.]/g, '-')}.log`); }}><i className="bi bi-download" aria-hidden="true" />下载当前日志</button><button type="button" className="secondary-button" disabled={busy === 'diagnostics'} onClick={() => void withBusy('diagnostics', async () => { const data = await api<{ content?: string; filename?: string }>('/hardware/diagnostics'); if (!data.content) throw new Error('诊断包内容为空'); downloadText(`${data.content}\n`, data.filename || 'ugreen-led-diagnostics.txt'); onToast('硬件诊断包已生成并开始下载'); })}><i className="bi bi-file-earmark-arrow-down" aria-hidden="true" />一键下载诊断包</button><button type="button" className="danger-button" disabled={busy === 'clear'} onClick={() => { if (window.confirm('确定清空 app.log 及其轮转历史吗？此操作无法撤销。')) void withBusy('clear', async () => { const result = await api<{ message?: string }>('/logs/clear', { method: 'POST', query: 'confirm=clear-logs', body: '' }); onToast(result.message || '应用诊断日志已清空'); await loadLogs(); }); }}><i className="bi bi-trash3" aria-hidden="true" />清空</button></div><pre className="log-console" tabIndex={0}>{logs?.content || '正在读取应用日志…'}</pre><div className="log-footnote"><span>app.log · {bytes(logs?.size_bytes)} · {logs?.updated_at ? `更新于 ${new Date(Number(logs.updated_at) * 1000).toLocaleString()}` : '尚无日志'}{logs?.clipped ? ' · 输出已截断' : ''}</span><span>DEBUG 用完后建议恢复 INFO。</span></div></article>
    </div>
  </section>;
}
