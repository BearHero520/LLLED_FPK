import { formatRate } from '../lib/ini';

export type StatusData = {
  daemon?: string;
  mode?: string;
  network?: string;
  network_label?: string;
  net_rx_kbps?: number;
  net_tx_kbps?: number;
  net_domestic?: number;
  net_overseas?: number;
  led_status?: string;
};

export type MappingItem = {
  device?: string;
  led?: string;
  state?: string;
  read_kbps?: number;
  write_kbps?: number;
};

const modeLabels: Record<string, string> = { off: '关闭全部', on: '开启全部', smart: '智能模式' };
const networkLabels: Record<string, string> = { disconnected: '断网', connected: '联网', vpn: '外网' };
const diskStateLabels: Record<string, string> = {
  active: '活动', idle: '空闲', standby: '休眠', deep_sleep: '深度睡眠', offline: '离线', unknown: '未知', error: '异常', '?': '未知',
};

function StateChip({ state }: { state?: string }) {
  const key = String(state || 'unknown').trim();
  return <span className={`state-chip ${key || 'unknown'}`}>{diskStateLabels[key] || key || '未知'}</span>;
}

export function OverviewPage({
  hidden,
  status,
  mapping,
  onDevices,
}: {
  hidden: boolean;
  status: StatusData | null;
  mapping: MappingItem[];
  onDevices: () => void;
}) {
  const running = status?.daemon === 'running';
  const network = status?.network_label || networkLabels[status?.network || ''] || status?.network || '未知';
  const networkDebug = status
    ? `国内：${Number(status.net_domestic) ? '可达' : '不可达'} · 外网：${Number(status.net_overseas) ? '可达' : '不可达'}`
    : '等待网络探测结果';

  return (
    <section className="react-view" hidden={hidden} aria-label="概览">
      <div className="status-strip glass-surface">
        <div className="status-primary">
          <span className="surface-icon"><i className="bi bi-stars" aria-hidden="true" /></span>
          <div>
            <span className="surface-label">灯控状态</span>
            <strong>{status ? (running ? '应用运行中' : '后台已停止') : '正在读取'}</strong>
          </div>
        </div>
        <div className="status-facts">
          <div><span>当前模式</span><strong>{modeLabels[status?.mode || ''] || status?.mode || '—'}</strong></div>
          <div><span>网络状态</span><strong>{network}</strong></div>
          <div><span>已映射硬盘</span><strong>{mapping.length} 块</strong></div>
        </div>
      </div>

      <div className="overview-grid">
        <article className="glass-surface network-panel">
          <div className="section-heading">
            <div><span className="section-kicker">NETWORK</span><h2>实时网速</h2></div>
            <span className="soft-badge">{status ? network : '检测中'}</span>
          </div>
          <div className="speed-metrics">
            <div className="speed-metric download">
              <span className="metric-icon"><i className="bi bi-arrow-down" aria-hidden="true" /></span>
              <div><span>下载</span><strong>{formatRate(status?.net_rx_kbps)}</strong></div>
            </div>
            <div className="speed-divider" />
            <div className="speed-metric upload">
              <span className="metric-icon"><i className="bi bi-arrow-up" aria-hidden="true" /></span>
              <div><span>上传</span><strong>{formatRate(status?.net_tx_kbps)}</strong></div>
            </div>
          </div>
          <div className="network-footnote">{networkDebug}</div>
        </article>

        <article className="glass-surface disk-panel">
          <div className="section-heading">
            <div><span className="section-kicker">STORAGE</span><h2>硬盘活动</h2></div>
            <button type="button" className="text-button" onClick={onDevices}>查看映射 <i className="bi bi-chevron-right" aria-hidden="true" /></button>
          </div>
          <div className="table-scroll">
            <table className="data-table">
              <thead><tr><th>设备</th><th>盘位</th><th>状态</th><th>读取</th><th>写入</th></tr></thead>
              <tbody>
                {mapping.length ? mapping.map((item, index) => (
                  <tr key={`${item.device || 'disk'}-${index}`}>
                    <td>{item.device || '—'}</td><td>{item.led || '—'}</td><td><StateChip state={item.state} /></td>
                    <td>{formatRate(item.read_kbps)}</td><td>{formatRate(item.write_kbps)}</td>
                  </tr>
                )) : <tr><td className="empty-row" colSpan={5}>暂未检测到硬盘映射</td></tr>}
              </tbody>
            </table>
          </div>
        </article>
      </div>
    </section>
  );
}
