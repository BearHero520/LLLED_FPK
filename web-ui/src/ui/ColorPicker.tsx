import { useState } from "react";
import { Popover } from "@base-ui/react/popover";
import { HexColorPicker } from "react-colorful";

const swatches = ["#ffffff", "#ff3b30", "#ff9500", "#ffcc00", "#34c759", "#007aff", "#af52de", "#000000"];
export function ColorPicker({ label, value, onChange }: { label: string; value: string; onChange: (value: string) => void }) {
  const [open, setOpen] = useState(false);
  const [draft, setDraft] = useState(value);
  const [text, setText] = useState(value);
  const valid = /^#[0-9a-f]{6}$/i.test(text);
  const choose = (color: string) => { setDraft(color); setText(color); };
  const apply = () => { if (valid) { onChange(text.toLowerCase()); setOpen(false); } };
  return <Popover.Root open={open} onOpenChange={(next) => { if (next) choose(value); setOpen(next); }}>
    <Popover.Trigger className="color-picker-trigger" aria-label={`${label}，${value}`} title={`${label} ${value}`}>
      <span style={{ backgroundColor: value }} /><i className="bi bi-palette" aria-hidden="true" />
    </Popover.Trigger>
    <Popover.Portal><Popover.Positioner className="color-picker-positioner" sideOffset={10}>
      <Popover.Popup className="color-picker-popup">
        <Popover.Title className="color-picker-title">{label}</Popover.Title>
        <Popover.Description className="color-picker-description">拖动色板选色，或输入 HEX 色值。</Popover.Description>
        <HexColorPicker color={draft} onChange={choose} />
        <div className="color-picker-swatches" role="group" aria-label="常用颜色">{swatches.map((color) =>
          <button type="button" key={color} style={{ backgroundColor: color }} aria-label={`选择颜色 ${color}`}
            aria-pressed={draft.toLowerCase() === color} onClick={() => choose(color)} />)}</div>
        <label className="color-picker-hex"><span>HEX</span><input aria-label={`${label} HEX`} value={text} maxLength={7} spellCheck={false} autoComplete="off" aria-invalid={!valid}
          onChange={(event) => { const next = event.target.value; setText(next); if (/^#[0-9a-f]{6}$/i.test(next)) setDraft(next); }}
          onKeyDown={(event) => { if (event.key === "Enter") apply(); }} /></label>
        {!valid && <p className="color-picker-error" role="status">请输入 # 加 6 位色值，例如 #007AFF。</p>}
        <div className="color-picker-actions"><Popover.Close className="secondary-button">取消</Popover.Close><button type="button" className="primary-button" disabled={!valid} onClick={apply}>使用此颜色</button></div>
        <p className="color-picker-footnote">保存灯光设置后生效</p>
      </Popover.Popup>
    </Popover.Positioner></Popover.Portal>
  </Popover.Root>;
}
