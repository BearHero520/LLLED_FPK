import { useCallback, useEffect, useMemo, useState } from 'react';
import { api } from '../lib/api';

type LabSlot = { led: string; position?: number };
type LabDisk = { device: string; hctl: string; serial?: string; model?: string; size?: string; position?: number; supported?: boolean; position_supported?: boolean; identity_supported?: boolean };
type LabData = { active?: boolean; mode?: string; product_name?: string; profile?: string; slots?: LabSlot[]; disks?: LabDisk[]; message?: string };
type Toast = (message: string, type?: 'ok' | 'err') => void;
type Method = 'position' | 'disk';

export function LabPage({ hidden, onToast, onRefresh }: { hidden: boolean; onToast: Toast; onRefresh: () => Promise<void> }) {
  const [lab, setLab] = useState<LabData>({});
  const [method, setMethod] = useState<Method>('position');
  const [draft, setDraft] = useState<Record<string, string>>({});
  const [identifying, setIdentifying] = useState('');
  const [busy, setBusy] = useState<string | null>(null);

  const load = useCallback(async () => {
    const data = await api<LabData>('/lab/mapping/status');
    setLab(data);
    if (data.mode === 'disk' || data.mode === 'position') setMethod(data.mode);
    return data;
  }, []);
  useEffect(() => { if (!hidden) void load().catch((error) => onToast(error instanceof Error ? error.message : '读取实验室状态失败', 'err')); }, [hidden, load, onToast]);

  const slots = lab.slots || [];
  const disks = lab.disks || [];
  const used = useMemo(() => new Set(Object.values(draft).filter(Boolean)), [draft]);
  const mappedCount = Object.values(draft).filter(Boolean).length;
  const keys = method === 'position' ? disks.filter((disk) => disk.position_supported !== false).map((disk) => disk.hctl) : slots.map((slot) => slot.led);
  const validCount = keys.filter((key) => draft[key]).length;
  const run = async (name: string, action: () => Promise<void>) => { setBusy(name); try { await action(); } catch (error) { onToast(error instanceof Error ? error.message : '实验室操作失败', 'err'); } finally { setBusy(null); } };
  const start = async () => {
    const data = await api<LabData>('/lab/mapping/start', { method: 'POST', body: '' });
    setLab(data); setDraft({}); setIdentifying(''); onToast(data.message || '检测模式已启动，全部硬盘灯已点亮');
  };
  const highlight = async (led: string) => {
    const data = await api<LabData>('/lab/mapping/highlight', { method: 'POST', query: `led=${encodeURIComponent(led)}`, body: '' });
    setLab(data); setIdentifying(led); onToast(data.message || `${led} 正在闪烁`);
  };
  const save = async () => {
    const lines = method === 'position'
      ? disks.map((disk) => { const led = draft[disk.hctl]; return led && disk.position_supported !== false ? `${led}|${disk.device}|${disk.hctl}` : ''; }).filter(Boolean)
      : slots.map((slot) => { const device = draft[slot.led]; const disk = disks.find((item) => item.device === device); return disk?.identity_supported !== false && device ? `${slot.led}|${device}|${disk?.serial || ''}` : ''; }).filter(Boolean);
    if (!lines.length) { onToast('请至少完成一个有效绑定', 'err'); return; }
    const path = method === 'position' ? '/lab/position/save' : '/lab/mapping/save';
    const data = await api<LabData>(path, { method: 'POST', body: lines.join('\n') });
    setLab(data); setDraft({}); setIdentifying(''); onToast(data.message || '自定义映射已保存'); await onRefresh();
  };
  const changeMethod = (next: Method) => { if (!lab.active) { setMethod(next); setDraft({}); } };
  const selectPosition = (hctl: string, led: string) => setDraft((current) => ({ ...current, [hctl]: led }));
  const selectDisk = (led: string, device: string) => setDraft((current) => ({ ...current, [led]: device }));

  return <section className="react-view" hidden={hidden} aria-label="实验室">
    <div className="lab-warning glass-surface" role="note"><span className="surface-icon warning"><i className="bi bi-exclamation-triangle" aria-hidden="true" /></span><div><div className="lab-warning-title"><strong>实验室</strong><span className="warning-badge">未经验证 · 谨慎使用</span></div><p>检测时会临时接管硬盘灯。请确认机箱旁无人维护，再开始操作。</p></div></div>
    <div className="lab-layout">
      <article className="glass-surface lab-intro-surface"><div className="section-heading"><div><span className="section-kicker">LED MAPPING LAB</span><h2>硬盘灯绑定</h2></div><span className="soft-badge">{lab.active ? '检测模式' : lab.mode === 'auto' ? '自动映射' : method === 'position' ? '按位置绑定' : '按硬盘绑定'}</span></div>
        <div className="lab-method-tabs" role="tablist" aria-label="硬盘灯绑定方式"><button type="button" className={`lab-method-tab${method === 'position' ? ' active' : ''}`} role="tab" aria-selected={method === 'position'} disabled={Boolean(lab.active)} onClick={() => changeMethod('position')}><i className="bi bi-hdd-rack" aria-hidden="true" /><span><strong>按位置绑定</strong><small>换硬盘不受影响 · 推荐</small></span></button><button type="button" className={`lab-method-tab${method === 'disk' ? ' active' : ''}`} role="tab" aria-selected={method === 'disk'} disabled={Boolean(lab.active)} onClick={() => changeMethod('disk')}><i className="bi bi-device-hdd" aria-hidden="true" /><span><strong>按硬盘绑定</strong><small>映射跟随硬盘序列号</small></span></button></div>
        <p className="surface-help">{method === 'position' ? '将 HCTL 代表的硬盘位置绑定到实际 LED 通道，适合 6/8 盘位灯光乱序的机型。' : '为每个 LED 通道选择一块硬盘；映射会与硬盘序列号一起保存。'}</p>
        <ol className="lab-steps" aria-label="绑定流程"><li><span>1</span><div><strong>点亮全部硬盘灯</strong><small>确认所有盘位灯可见并进入检测模式</small></div></li><li><span>2</span><div><strong>{method === 'position' ? '逐位置选择 LED' : '逐通道选择硬盘'}</strong><small>选择后闪烁对应 LED 验证</small></div></li><li><span>3</span><div><strong>检查并保存</strong><small>重复绑定会被阻止，保存后立即生效</small></div></li></ol>
        <div className="lab-current-summary">当前机型：{lab.product_name || '正在读取'} · {lab.active ? '检测模式进行中' : '未接管灯光'}</div><div className="lab-intro-actions"><button type="button" className="primary-button" disabled={busy === 'start' || Boolean(lab.active)} onClick={() => void run('start', start)}><i className="bi bi-lightbulb" aria-hidden="true" />开始检测并点亮全部硬盘灯</button><button type="button" className="secondary-button" disabled={busy === 'reset'} onClick={() => { if (window.confirm('确定恢复自动 HCTL 映射吗？已保存的自定义盘位规则将停用。')) void run('reset', async () => { const data = await api<LabData>('/lab/mapping/reset', { method: 'POST', body: '' }); setLab(data); setDraft({}); onToast(data.message || '已恢复自动映射'); await onRefresh(); }); }}><i className="bi bi-arrow-counterclockwise" aria-hidden="true" />恢复自动映射</button></div>
      </article>
      <article className="glass-surface lab-session-surface" hidden={!lab.active}><div className="lab-session-head"><div><span className="section-kicker">DETECTION MODE</span><h2>检测模式进行中</h2><p className="surface-help">先确认全部硬盘灯已亮，再为每个目标选择对应的 LED 通道。</p></div><span className="session-live"><span className="status-dot online" />临时接管中</span></div><div className="lab-session-toolbar"><div className="lab-progress"><strong>已绑定 {mappedCount} 个{method === 'position' ? '位置' : '通道'}</strong><span>{validCount ? '可以保存当前选择' : '请选择至少一个有效绑定'}</span></div><button type="button" className="secondary-button" disabled={busy === 'all'} onClick={() => void run('all', start)}><i className="bi bi-brightness-high" aria-hidden="true" />重新点亮全部</button></div>
        <div className="lab-mapping-layout">{method === 'position' ? <div className="lab-slot-panel"><div className="lab-panel-heading"><strong>硬盘位置与 LED</strong><span>选择后点击“闪烁此灯”验证</span></div><div className="lab-slot-list">{disks.filter((disk) => disk.position_supported !== false).map((disk) => { const selected = draft[disk.hctl] || ''; return <div className="lab-slot-row" key={disk.hctl}><div><strong>{disk.device} · 位置 {disk.position || '—'}</strong><small>{disk.model || '未知硬盘'} · {disk.hctl}</small></div><select className="hardware-select" value={selected} onChange={(event) => selectPosition(disk.hctl, event.target.value)}><option value="">选择 LED 通道</option>{slots.map((slot) => <option key={slot.led} value={slot.led} disabled={slot.led !== selected && used.has(slot.led)}>{slot.led}</option>)}</select><button type="button" className="secondary-button" disabled={!selected || busy === `flash-${selected}`} onClick={() => void run(`flash-${selected}`, () => highlight(selected))}><i className="bi bi-lightning-charge" aria-hidden="true" />{identifying === selected ? '正在闪烁' : '闪烁此灯'}</button></div>; })}</div></div> : <div className="lab-slot-panel"><div className="lab-panel-heading"><strong>LED 通道与硬盘</strong><span>每个硬盘只能分配一次</span></div><div className="lab-slot-list">{slots.map((slot) => { const selected = draft[slot.led] || ''; return <div className="lab-slot-row" key={slot.led}><div><strong>{slot.led} · 位置 {slot.position || '—'}</strong><small>按硬盘序列号保存</small></div><select className="hardware-select" value={selected} onChange={(event) => selectDisk(slot.led, event.target.value)}><option value="">选择硬盘</option>{disks.filter((disk) => disk.identity_supported !== false).map((disk) => <option key={disk.device} value={disk.device} disabled={disk.device !== selected && used.has(disk.device)}>{disk.device} · {disk.serial || disk.model || '未知'}</option>)}</select><button type="button" className="secondary-button" disabled={busy === `flash-${slot.led}`} onClick={() => void run(`flash-${slot.led}`, () => highlight(slot.led))}><i className="bi bi-lightning-charge" aria-hidden="true" />{identifying === slot.led ? '正在闪烁' : '闪烁此灯'}</button></div>; })}</div></div>}<aside className="lab-inventory-panel"><div className="lab-panel-heading"><strong>LED 通道分配</strong><span>当前选择</span></div><div className="lab-disk-inventory">{slots.map((slot) => <div key={slot.led} className="lab-inventory-row"><strong>{slot.led}</strong><span>{method === 'position' ? (disks.find((disk) => draft[disk.hctl] === slot.led)?.device || '未分配') : (draft[slot.led] || '未分配')}</span></div>)}</div></aside></div>
        <div className="lab-validation" role="alert">{validCount ? `已完成 ${validCount} 项绑定；保存前请逐项闪烁确认。` : '尚未选择绑定关系。'}</div><div className="lab-session-actions"><button type="button" className="secondary-button" disabled={busy === 'cancel'} onClick={() => { if (window.confirm('确定取消本次检测吗？尚未保存的盘位选择会丢失。')) void run('cancel', async () => { const data = await api<LabData>('/lab/mapping/cancel', { method: 'POST', body: '' }); setLab(data); setDraft({}); setIdentifying(''); onToast(data.message || '已退出检测模式'); }); }}><i className="bi bi-x-lg" aria-hidden="true" />取消并退出</button><button type="button" className="primary-button" disabled={!validCount || busy === 'save'} onClick={() => void run('save', save)}><i className="bi bi-floppy" aria-hidden="true" />保存自定义映射</button></div>
      </article>
    </div>
  </section>;
}
