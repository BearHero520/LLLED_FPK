import { Fragment, useCallback, useEffect, useState, type ReactNode } from 'react';
import { api } from '../lib/api';
import { updateState } from '../lib/version';
import { readmeInlineTokens, readmeRepositoryUrl } from '../lib/readme';

export type AboutInfo = {
  display_name?: string;
  version?: string;
  maintainer?: string;
  license?: string;
  repository_url?: string;
  readme_url?: string;
  qq_group?: string;
};

type UpdateData = {
  reachable?: boolean;
  current_version?: string;
  latest_version?: string;
  release_url?: string;
  download_url?: string;
  checked_at?: number;
};
type ReadmeData = {
  content?: string;
  source_url?: string;
  reachable?: boolean;
  cached?: boolean;
  fetched_at?: number;
};
type Toast = (message: string, type?: 'ok' | 'err') => void;

const repositoryUrl = readmeRepositoryUrl;

function InlineMarkdown({ text }: { text: string }) {
  return <>{readmeInlineTokens(text).map((token, index) => {
    if (token.kind === 'strong') return <strong key={index}>{token.text}</strong>;
    if (token.kind === 'code') return <code key={index}>{token.text}</code>;
    if (token.kind === 'image') return <a key={index} href={token.src} target="_blank" rel="noopener noreferrer"><img src={token.src} alt={token.text} loading="lazy" width="260" /></a>;
    if (token.kind === 'link') return <a key={index} href={token.href} target="_blank" rel="noopener noreferrer">{token.text}</a>;
    return <Fragment key={index}>{token.text}</Fragment>;
  })}</>;
}

function MarkdownDocument({ content }: { content: string }) {
  const lines = content.replace(/\r\n?/g, '\n').split('\n');
  const blocks: ReactNode[] = [];
  let index = 0;
  while (index < lines.length) {
    const line = lines[index];
    if (!line.trim()) { index += 1; continue; }
    if (line.startsWith('```')) {
      const code: string[] = [];
      index += 1;
      while (index < lines.length && !lines[index].startsWith('```')) code.push(lines[index++]);
      index += 1;
      blocks.push(<pre key={`code-${index}`}><code>{code.join('\n')}</code></pre>);
      continue;
    }
    const heading = line.match(/^(#{1,4})\s+(.+)$/);
    if (heading) {
      const level = heading[1].length;
      const children = <InlineMarkdown text={heading[2]} />;
      blocks.push(level === 1 ? <h1 key={index}>{children}</h1> : level === 2 ? <h2 key={index}>{children}</h2> : level === 3 ? <h3 key={index}>{children}</h3> : <h4 key={index}>{children}</h4>);
      index += 1;
      continue;
    }
    if (/^\|.*\|$/.test(line) && /^\|?[\s:|-]+\|?$/.test(lines[index + 1] || '')) {
      const rows: string[][] = [];
      const header = line.split('|').slice(1, -1).map((cell) => cell.trim());
      index += 2;
      while (index < lines.length && /^\|.*\|$/.test(lines[index])) rows.push(lines[index++].split('|').slice(1, -1).map((cell) => cell.trim()));
      blocks.push(<div className="readme-table-wrap" key={`table-${index}`}><table><thead><tr>{header.map((cell, cellIndex) => <th key={cellIndex}><InlineMarkdown text={cell} /></th>)}</tr></thead><tbody>{rows.map((row, rowIndex) => <tr key={rowIndex}>{row.map((cell, cellIndex) => <td key={cellIndex}><InlineMarkdown text={cell} /></td>)}</tr>)}</tbody></table></div>);
      continue;
    }
    if (/^[-*]\s+/.test(line)) {
      const items: string[] = [];
      while (index < lines.length && /^[-*]\s+/.test(lines[index])) items.push(lines[index++].replace(/^[-*]\s+/, ''));
      blocks.push(<ul key={`list-${index}`}>{items.map((item, itemIndex) => <li key={itemIndex}><InlineMarkdown text={item} /></li>)}</ul>);
      continue;
    }
    if (/^\d+[.]\s+/.test(line)) {
      const items: string[] = [];
      while (index < lines.length && /^\d+[.]\s+/.test(lines[index])) items.push(lines[index++].replace(/^\d+[.]\s+/, ''));
      blocks.push(<ol key={`ordered-${index}`}>{items.map((item, itemIndex) => <li key={itemIndex}><InlineMarkdown text={item} /></li>)}</ol>);
      continue;
    }
    const paragraph = [line.trim()];
    index += 1;
    while (index < lines.length && lines[index].trim() && !/^(#{1,4})\s+|^```|^[-*]\s+|^\d+[.]\s+|^\|.*\|$/.test(lines[index])) paragraph.push(lines[index++].trim());
    blocks.push(<p key={`paragraph-${index}`}><InlineMarkdown text={paragraph.join(' ')} /></p>);
  }
  return <div className="readme-document">{blocks}</div>;
}

export function AboutPage({ hidden, info, onToast }: { hidden: boolean; info: AboutInfo | null; onToast: Toast }) {
  const [update, setUpdate] = useState<UpdateData | null>(null);
  const [readme, setReadme] = useState<ReadmeData | null>(null);
  const [readmeError, setReadmeError] = useState('');
  const [busy, setBusy] = useState<string | null>(null);

  const checkUpdate = useCallback(async (force = false) => {
    const data = await api<UpdateData>('/update/check', { query: force ? 'force=1' : '' });
    setUpdate(data);
    return data;
  }, []);
  const loadReadme = useCallback(async (force = false) => {
    try {
      const data = await api<ReadmeData>('/about/readme', { query: force ? 'force=1' : '' });
      setReadme(data);
      setReadmeError('');
      return data;
    } catch (error) {
      setReadmeError(error instanceof Error ? error.message : '无法从 GitHub 获取 README.md');
      throw error;
    }
  }, []);
  useEffect(() => {
    if (hidden) return;
    void checkUpdate().catch(() => {});
    void loadReadme().catch(() => {});
  }, [checkUpdate, hidden, loadReadme]);

  const withBusy = async (name: string, action: () => Promise<void>) => {
    setBusy(name);
    try { await action(); } catch (error) { onToast(error instanceof Error ? error.message : '操作失败', 'err'); } finally { setBusy(null); }
  };
  const currentVersion = String(update?.current_version || info?.version || '—').replace(/^v/i, '');
  const updateStatus = updateState(currentVersion, update?.latest_version, update?.reachable);
  const sourceUrl = readme?.source_url || info?.readme_url || `${repositoryUrl}/blob/main/README.md`;

  return <section className="react-view" hidden={hidden} aria-label="关于">
    <div className="about-layout">
      <article className="glass-surface about-hero-surface">
        <img src="./images/logo.png?v=2.1.0-toolbox" alt="UGreen Control" className="about-logo" width="112" height="112" />
        <div className="about-brand-copy"><span className="section-kicker">UGREEN NAS SYSTEM TOOLBOX</span><h2>{info?.display_name || 'UGreen Control'}</h2><p>面向飞牛 fnOS 的绿联 NAS 灯光、硬件监控与 BIOS 管理工具。</p><div className="about-badges"><span>v{currentVersion}</span><span>{info?.license || 'AGPL-3.0'}</span><span>BearHero</span></div></div>
        <div className="about-contact"><span><i className="bi bi-people" aria-hidden="true" />测试 QQ 群</span><strong>{info?.qq_group || '1108837172'}</strong><small>欢迎反馈机型兼容性与测试记录</small></div>
      </article>

      <article className="glass-surface update-surface about-update-surface"><div className="section-heading"><div><span className="section-kicker">APPLICATION UPDATE</span><h2>应用更新</h2></div><span className="soft-badge">{updateStatus.badge}</span></div><div className="update-content"><div className="update-copy"><div className="update-version"><span>当前版本</span><strong>v{currentVersion}</strong></div><h3>{updateStatus.title}</h3><p className="surface-help">发现新版本后，可下载安装包并在 fnOS 应用中心手动升级。</p><small>{update?.checked_at ? `检查于 ${new Date(Number(update.checked_at) * 1000).toLocaleString()}` : '不会自动安装，也不会在后台静默升级。'}</small></div><div className="update-actions"><button type="button" className="secondary-button" disabled={busy === 'update'} onClick={() => void withBusy('update', async () => { const data = await checkUpdate(true); onToast(data.reachable === false ? '暂时无法连接 GitHub Release' : '更新检查完成', data.reachable === false ? 'err' : 'ok'); })}><i className="bi bi-arrow-clockwise" aria-hidden="true" />检查更新</button>{update?.release_url ? <a className="secondary-button" href={String(update.release_url)} target="_blank" rel="noopener noreferrer"><i className="bi bi-card-text" aria-hidden="true" />更新说明</a> : null}{updateStatus.available && update?.download_url ? <a className="primary-button" href={String(update.download_url)} target="_blank" rel="noopener noreferrer"><i className="bi bi-download" aria-hidden="true" />下载升级包</a> : null}</div></div></article>

      <article className="glass-surface readme-surface"><div className="section-heading"><div><span className="section-kicker">GITHUB README</span><h2>项目说明</h2><p className="surface-help">内容直接获取自 GitHub 仓库的 README.md。</p></div><span className="soft-badge">{readmeError ? '获取失败' : readme?.cached ? '缓存内容' : readme?.content ? 'GitHub 最新内容' : '正在获取'}</span></div><div className="readme-toolbar"><a className="secondary-button" href={sourceUrl} target="_blank" rel="noopener noreferrer"><i className="bi bi-github" aria-hidden="true" />在 GitHub 查看</a><button type="button" className="secondary-button" disabled={busy === 'readme'} onClick={() => void withBusy('readme', async () => { await loadReadme(true); onToast('README 已从 GitHub 刷新'); })}><i className="bi bi-arrow-clockwise" aria-hidden="true" />刷新 README</button></div>{readme?.content ? <MarkdownDocument content={readme.content} /> : <div className={`readme-loading${readmeError ? ' error' : ''}`}><i className={`bi ${readmeError ? 'bi-cloud-slash' : 'bi-cloud-download'}`} aria-hidden="true" /><span>{readmeError || '正在从 GitHub 获取 README.md…'}</span></div>}</article>
    </div>
  </section>;
}
