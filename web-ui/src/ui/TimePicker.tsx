import { useCallback, useState } from "react";
import { Popover } from "@base-ui/react/popover";

const pad = (n: number) => String(n).padStart(2, "0");
export function TimePicker({ label, value, onChange }: { label: string; value: string; onChange: (value: string) => void }) {
  const [open, setOpen] = useState(false);
  const [draft, setDraft] = useState(value);
  const valid = /^([01]\d|2[0-3]):[0-5]\d$/.test(draft);
  const [hour, minute] = valid ? draft.split(":").map(Number) : [0, 0];
  const scrollSelected = useCallback((element: HTMLDivElement | null) => { if (element) { const selected = element.querySelector<HTMLElement>('[aria-pressed="true"]'); if (selected) element.scrollTop = selected.offsetTop - 72; } }, []);
  const choose = (column: number, n: number) => setDraft(column === 0 ? `${pad(n)}:${pad(minute)}` : `${pad(hour)}:${pad(n)}`);
  return <Popover.Root open={open} onOpenChange={(next) => { if (next) setDraft(value); setOpen(next); }}>
    <Popover.Trigger className="time-picker-trigger" aria-label={`${label}，${value}`}>
      <span>{value}</span><i className="bi bi-clock" aria-hidden="true" />
    </Popover.Trigger>
    <Popover.Portal><Popover.Positioner sideOffset={10} className="time-picker-positioner">
      <Popover.Popup className="time-picker-popup">
        <Popover.Title className="time-picker-title">{label}</Popover.Title>
        <Popover.Description className="time-picker-description">24 小时制 · 使用 NAS 系统时间</Popover.Description>
        <input className="time-picker-input" aria-label={`${label}时间输入`} value={draft} maxLength={5} placeholder="HH:MM"
          onChange={(event) => setDraft(event.target.value)} aria-invalid={!valid}
          onKeyDown={(event) => { if (event.key === "Enter" && valid) { onChange(draft); setOpen(false); } }} />
        <div className="time-picker-columns">{[24, 60].map((count, column) => <div key={column}>
          <div className="time-picker-column-title">{column === 0 ? "小时" : "分钟"}</div>
          <div className="time-picker-scroll" role="group" aria-label={column === 0 ? "小时" : "分钟"}
            ref={scrollSelected}>
            {Array.from({ length: count }, (_, n) => <button key={n} type="button" aria-label={`${pad(n)}${column === 0 ? "时" : "分"}`}
              aria-pressed={valid && n === (column === 0 ? hour : minute)} onClick={() => choose(column, n)}
              onKeyDown={(event) => {
                const target = event.key === "ArrowDown" ? (n + 1) % count : event.key === "ArrowUp" ? (n + count - 1) % count : event.key === "Home" ? 0 : event.key === "End" ? count - 1 : -1;
                if (target >= 0) { event.preventDefault(); choose(column, target); (event.currentTarget.parentElement?.children[target] as HTMLElement)?.focus(); }
              }}>{pad(n)}</button>)}
          </div>
        </div>)}</div>
        {!valid && <p className="time-picker-error" role="status">请输入有效时间，例如 07:30。</p>}
        <div className="time-picker-actions"><Popover.Close className="secondary-button">取消</Popover.Close>
          <button type="button" className="primary-button" disabled={!valid} onClick={() => { onChange(draft); setOpen(false); }}>确定时间</button></div>
      </Popover.Popup>
    </Popover.Positioner></Popover.Portal>
  </Popover.Root>;
}
