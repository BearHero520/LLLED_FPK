import { Slider } from "@base-ui/react/slider";

export function BrightnessSlider({ label, value, onChange, min = 0, disabled = false, prefix = "" }: {
  label: string; value: number; onChange: (value: number) => void;
  min?: number; disabled?: boolean; prefix?: string;
}) {
  return <Slider.Root className="glass-brightness" value={value} min={min} max={255} step={1} disabled={disabled}
    onValueChange={onChange}>
    <Slider.Control className="glass-brightness-control">
      <Slider.Track className="glass-brightness-track">
        <Slider.Indicator className="glass-brightness-fill" />
        <Slider.Thumb className="glass-brightness-thumb" aria-label={label}
          getAriaValueText={(_, current) => `${prefix}${current} / 255，${Math.round(current / 255 * 100)}%`}>
          <span className="glass-brightness-tooltip" aria-hidden="true"><strong>{prefix}{value}</strong><small>{Math.round(value / 255 * 100)}%</small></span>
        </Slider.Thumb>
      </Slider.Track>
    </Slider.Control>
  </Slider.Root>;
}
