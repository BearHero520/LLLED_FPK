import { useState } from 'react';
import { boundedInt, mergeIni, type IniData } from '../lib/ini';

type Toast = (message: string, type?: 'ok' | 'err') => void;

export function ActivityPage({ hidden, settings, onSettingsChange, onSave, onToast }: {
  hidden: boolean;
  settings: IniData;
  onSettingsChange: (settings: IniData) => void;
  onSave: (lines: string[], successMessage: string) => Promise<void>;
  onToast: Toast;
}) {
  const [saving, setSaving] = useState(false);
  const diskBlink = settings.activity?.disk_blink === 'true';
  const networkBlink = settings.activity?.network_blink === 'true';
  const diskThreshold = boundedInt(settings.activity?.disk_threshold_kbps, 1, 1048576, 128);
  const networkThreshold = boundedInt(settings.activity?.network_threshold_kbps, 1, 1048576, 32);
  const update = (patch: Record<string, string>) => onSettingsChange(mergeIni(settings, { activity: patch }));
  const save = async () => {
    setSaving(true);
    try {
      await onSave([
        `activity.disk_blink=${diskBlink}`,
        `activity.network_blink=${networkBlink}`,
        `activity.disk_threshold_kbps=${diskThreshold}`,
        `activity.network_threshold_kbps=${networkThreshold}`,
      ], '活动设置已保存');
    } catch (error) { onToast(error instanceof Error ? error.message : '保存活动设置失败', 'err'); } finally { setSaving(false); }
  };

  return <section className="react-view" hidden={hidden} aria-label="活动提示">
    <div className="activity-layout">
      <article className="glass-surface activity-card">
        <div className="activity-card-head"><span className="surface-icon blue"><i className="bi bi-device-hdd" aria-hidden="true" /></span><div><span className="section-kicker">DISK ACTIVITY</span><h2>磁盘读写闪动</h2></div><label className="native-check"><input type="checkbox" checked={diskBlink} onChange={(event) => update({ disk_blink: String(event.target.checked) })} /><span>启用</span></label></div>
        <p className="surface-help">读写速度超过阈值时，对应盘位灯会按速度分档闪动。</p>
        <label className="threshold-field"><span>触发阈值</span><span className="number-wrap"><input type="number" min="1" max="1048576" step="1" disabled={!diskBlink} value={diskThreshold} onChange={(event) => update({ disk_threshold_kbps: String(boundedInt(event.target.value, 1, 1048576, 128)) })} /><em>KB/s</em></span></label>
      </article>
      <article className="glass-surface activity-card">
        <div className="activity-card-head"><span className="surface-icon violet"><i className="bi bi-wifi" aria-hidden="true" /></span><div><span className="section-kicker">NETWORK ACTIVITY</span><h2>网络速度闪动</h2></div><label className="native-check"><input type="checkbox" checked={networkBlink} onChange={(event) => update({ network_blink: String(event.target.checked) })} /><span>启用</span></label></div>
        <p className="surface-help">上传和下载总速度超过阈值时，网络灯会提示当前流量。</p>
        <label className="threshold-field"><span>触发阈值</span><span className="number-wrap"><input type="number" min="1" max="1048576" step="1" disabled={!networkBlink} value={networkThreshold} onChange={(event) => update({ network_threshold_kbps: String(boundedInt(event.target.value, 1, 1048576, 32)) })} /><em>KB/s</em></span></label>
      </article>
      <article className="glass-surface tier-surface"><div><span className="section-kicker">BLINK SPEED</span><h2>闪动频率</h2><p className="surface-help">系统会根据实时速度自动选择低、中、高三档频率。</p></div><div className="tier-list"><span><i className="bi bi-circle-fill tier-low" aria-hidden="true" />刚刚超过阈值</span><span><i className="bi bi-circle-fill tier-mid" aria-hidden="true" />达到阈值 4 倍</span><span><i className="bi bi-circle-fill tier-high" aria-hidden="true" />达到阈值 16 倍</span></div></article>
    </div>
    <div className="view-actions"><button type="button" className="primary-button" disabled={saving} onClick={() => void save()}><i className="bi bi-floppy" aria-hidden="true" />{saving ? '正在保存…' : '保存活动设置'}</button></div>
  </section>;
}
