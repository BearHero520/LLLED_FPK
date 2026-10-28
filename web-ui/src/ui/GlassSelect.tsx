import { Select } from "@base-ui/react/select";

export type GlassSelectOption = { value: string; label: string; description?: string; icon?: string };
export function GlassSelect({ label, value, options, disabled, onValueChange }: {
  label: string; value: string; options: readonly GlassSelectOption[];
  disabled?: boolean; onValueChange?: (value: string) => void;
}) {
  return <Select.Root value={value} items={options} disabled={disabled}
    onValueChange={(next) => { if (next !== null) onValueChange?.(next); }}>
    <Select.Trigger className="glass-select-trigger" aria-label={label}>
      <Select.Value />
      <Select.Icon className="glass-select-chevron"><i className="bi bi-chevron-down" aria-hidden="true" /></Select.Icon>
    </Select.Trigger>
    <Select.Portal><Select.Positioner className="glass-select-positioner" sideOffset={8} alignItemWithTrigger={false}>
      <Select.Popup className="glass-select-popup">
        <Select.List className="glass-select-list">{options.map((option) =>
          <Select.Item key={option.value} value={option.value} className={`glass-select-option${option.icon ? "" : " glass-select-option-simple"}`}>
            {option.icon && <i className={`bi ${option.icon}`} aria-hidden="true" />}
            <span><Select.ItemText>{option.label}</Select.ItemText>{option.description && <small>{option.description}</small>}</span>
            <Select.ItemIndicator className="glass-select-check"><i className="bi bi-check2" aria-hidden="true" /></Select.ItemIndicator>
          </Select.Item>)}
        </Select.List>
      </Select.Popup>
    </Select.Positioner></Select.Portal>
  </Select.Root>;
}
