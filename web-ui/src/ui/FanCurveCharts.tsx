import { useEffect, useRef, useState, type RefObject } from "react";
import type { EChartsOption, LineSeriesOption } from "echarts";
import { LineChart } from "echarts/charts";
import {
  AriaComponent,
  GraphicComponent,
  GridComponent,
  LegendComponent,
  TooltipComponent,
} from "echarts/components";
import { init, use } from "echarts/core";
import { CanvasRenderer } from "echarts/renderers";
import { api } from "../lib/api";

use([
  LineChart,
  GridComponent,
  LegendComponent,
  TooltipComponent,
  GraphicComponent,
  AriaComponent,
  CanvasRenderer,
]);

export type FanCurveDraft = {
  minimum: number;
  cpu: string;
  hdd: string;
  ssd: string;
  pwm: string;
};

export type StockFanCurveData = {
  available?: boolean;
  profile?: string;
  cpu?: string;
  hdd?: string;
  ssd?: string;
  system_pwm?: string;
  cpu_pwm?: string;
};

type CurveKey = "cpu" | "hdd" | "ssd";
type CurveValues = Record<CurveKey, number[]> & { pwm: number[] };
type TelemetryRange = "1m" | "1h" | "24h";
type TelemetrySample = {
  at: number;
  cpu?: number;
  hdd?: number;
  ssd?: number;
  cpuRpm?: number;
  sysRpm?: number;
  sys2Rpm?: number;
};
type TelemetryKey = Exclude<keyof TelemetrySample, "at">;
type TelemetryCurve = {
  key: TelemetryKey;
  label: string;
  color: string;
  axis: "temperature" | "rpm";
};
type TooltipParam = {
  axisValue?: unknown;
  value?: unknown;
  seriesName?: string;
  marker?: string;
  seriesId?: string;
};

const curves: Array<{ key: CurveKey; label: string; color: string }> = [
  { key: "cpu", label: "CPU", color: "#1677ff" },
  { key: "hdd", label: "HDD", color: "#e89124" },
  { key: "ssd", label: "NVMe", color: "#1b9c68" },
];

const telemetryCurves: TelemetryCurve[] = [
  { key: "cpu", label: "CPU", color: "#1677ff", axis: "temperature" },
  { key: "hdd", label: "HDD", color: "#e89124", axis: "temperature" },
  { key: "ssd", label: "NVMe", color: "#1b9c68", axis: "temperature" },
  { key: "cpuRpm", label: "CPU 风扇", color: "#7357d8", axis: "rpm" },
  { key: "sysRpm", label: "系统风扇", color: "#0f8f9a", axis: "rpm" },
  { key: "sys2Rpm", label: "系统风扇 2", color: "#c25d8a", axis: "rpm" },
];

const axisLineColor = "rgba(88, 103, 122, 0.22)";
const gridLineColor = "rgba(88, 103, 122, 0.10)";
const axisTextColor = "#7b8a9c";

function clamp(value: number, lower: number, upper: number) {
  return Math.max(lower, Math.min(upper, value));
}

function parseCsv(source: string, expected: number, fallback: number[]) {
  const parsed = source
    .split(",")
    .map((part) => Number(part.trim()))
    .filter(Number.isFinite);
  return Array.from({ length: expected }, (_, index) =>
    Math.round(parsed[index] ?? fallback[index]),
  );
}

function curveValues(draft: FanCurveDraft, minPwm: number): CurveValues {
  const pwm = [
    clamp(Math.round(draft.minimum), minPwm, 255),
    ...parseCsv(draft.pwm, 4, [128, 204, 255, 255]),
  ];
  for (let index = 1; index < pwm.length; index += 1)
    pwm[index] = clamp(pwm[index], pwm[index - 1], 255);
  return {
    cpu: parseCsv(draft.cpu, 5, [50, 55, 75, 80, 90]),
    hdd: parseCsv(draft.hdd, 5, [40, 45, 50, 55, 70]),
    ssd: parseCsv(draft.ssd, 5, [45, 50, 60, 65, 70]),
    pwm,
  };
}

function toCsv(values: number[]) {
  return values.map((value) => Math.round(value)).join(",");
}

function tooltipParams(value: unknown): TooltipParam[] {
  return (Array.isArray(value) ? value : [value]).filter(
    (item): item is TooltipParam => Boolean(item && typeof item === "object"),
  );
}

function pairValue(value: unknown, index: number) {
  if (!Array.isArray(value)) return Number.NaN;
  return Number(value[index]);
}

function useEChart(
  containerRef: RefObject<HTMLDivElement | null>,
  enabled = true,
) {
  const chartRef = useRef<ReturnType<typeof init> | null>(null);

  useEffect(() => {
    if (!enabled) return;
    const container = containerRef.current;
    if (!container) return;
    const chart = init(container, undefined, {
      renderer: "canvas",
      useDirtyRect: true,
    });
    chartRef.current = chart;
    const observer =
      typeof ResizeObserver === "undefined"
        ? null
        : new ResizeObserver(() => chart.resize());
    observer?.observe(container);
    const resize = () => chart.resize();
    window.addEventListener("resize", resize);
    return () => {
      observer?.disconnect();
      window.removeEventListener("resize", resize);
      chart.dispose();
      chartRef.current = null;
    };
  }, [containerRef, enabled]);

  return chartRef;
}

function curveSeries(
  draft: FanCurveDraft,
  minPwm: number,
): LineSeriesOption[] {
  const values = curveValues(draft, minPwm);
  return curves.map((curve) => ({
    id: `curve-${curve.key}`,
    name: curve.label,
    type: "line",
    data: values[curve.key].map((temperature, index) => [
      temperature,
      values.pwm[index],
    ]),
    smooth: 0.16,
    symbol: "circle",
    symbolSize: 9,
    showSymbol: true,
    lineStyle: { width: 2.4, color: curve.color },
    itemStyle: {
      color: "#ffffff",
      borderColor: curve.color,
      borderWidth: 2,
    },
    emphasis: {
      focus: "series",
      lineStyle: { width: 3 },
      itemStyle: { borderWidth: 3 },
    },
  }));
}

function curveOption(
  draft: FanCurveDraft,
  minPwm: number,
  maxTemperature = 125,
): EChartsOption {
  return {
    animation: false,
    aria: { enabled: true },
    grid: { top: 20, right: 22, bottom: 52, left: 48, containLabel: false },
    legend: {
      bottom: 5,
      icon: "circle",
      itemWidth: 9,
      itemHeight: 9,
      itemGap: 18,
      textStyle: { color: "#5f6f86", fontSize: 10, fontWeight: 700 },
    },
    tooltip: {
      trigger: "item",
      confine: true,
      backgroundColor: "rgba(23, 32, 51, 0.94)",
      borderWidth: 0,
      padding: [9, 11],
      textStyle: { color: "#ffffff", fontSize: 11 },
      formatter: (input: unknown) => {
        const item = tooltipParams(input)[0];
        return `${item?.marker || ""}${item?.seriesName || ""}<br/>${Math.round(
          pairValue(item?.value, 0),
        )} °C · PWM ${Math.round(pairValue(item?.value, 1))}`;
      },
    },
    xAxis: {
      type: "value",
      min: 0,
      max: maxTemperature,
      name: "温度 °C",
      nameLocation: "middle",
      nameGap: 27,
      nameTextStyle: { color: axisTextColor, fontSize: 10, fontWeight: 700 },
      axisLine: { lineStyle: { color: axisLineColor } },
      axisTick: { show: false },
      axisLabel: { color: axisTextColor, fontSize: 9 },
      splitLine: { lineStyle: { color: gridLineColor } },
    },
    yAxis: {
      type: "value",
      min: minPwm,
      max: 255,
      name: "PWM",
      nameTextStyle: { color: axisTextColor, fontSize: 10, fontWeight: 700 },
      axisLine: { show: true, lineStyle: { color: axisLineColor } },
      axisTick: { show: false },
      axisLabel: { color: axisTextColor, fontSize: 9 },
      splitLine: { lineStyle: { color: gridLineColor } },
    },
    series: curveSeries(draft, minPwm),
  };
}

function updateCurvePoint(
  draft: FanCurveDraft,
  minPwm: number,
  curveKey: CurveKey,
  pointIndex: number,
  x: number,
  y: number,
) {
  const values = curveValues(draft, minPwm);
  const temperatures = [...values[curveKey]];
  const pwm = [...values.pwm];
  const lowerTemperature = pointIndex
    ? temperatures[pointIndex - 1] + 1
    : 0;
  const upperTemperature =
    pointIndex < temperatures.length - 1
      ? temperatures[pointIndex + 1] - 1
      : 125;
  const lowerPwm = pointIndex ? pwm[pointIndex - 1] : minPwm;
  const upperPwm =
    pointIndex < pwm.length - 1 ? pwm[pointIndex + 1] : 255;
  const temperature = clamp(
    Math.round(Number.isFinite(x) ? x : temperatures[pointIndex]),
    lowerTemperature,
    upperTemperature,
  );
  const nextPwm = clamp(
    Math.round(Number.isFinite(y) ? y : pwm[pointIndex]),
    lowerPwm,
    upperPwm,
  );
  temperatures[pointIndex] = temperature;
  pwm[pointIndex] = nextPwm;
  return {
    draft: {
      ...draft,
      [curveKey]: toCsv(temperatures),
      minimum: pwm[0],
      pwm: toCsv(pwm.slice(1)),
    } as FanCurveDraft,
    temperature,
    pwm: nextPwm,
  };
}

export function FanCurveEditor({
  draft,
  minPwm,
  disabled,
  onChange,
}: {
  draft: FanCurveDraft;
  minPwm: number;
  disabled: boolean;
  onChange: (next: FanCurveDraft) => void;
}) {
  const containerRef = useRef<HTMLDivElement | null>(null);
  const chartRef = useEChart(containerRef);
  const draftRef = useRef(draft);
  const pendingDraftRef = useRef(draft);
  const changeRef = useRef(onChange);
  const disabledRef = useRef(disabled);
  const [readout, setReadout] = useState(
    disabled
      ? "当前模式仅供预览。"
      : "拖动任意控制点，横轴为温度，纵轴为 PWM。",
  );

  useEffect(() => {
    changeRef.current = onChange;
  }, [onChange]);
  useEffect(() => {
    disabledRef.current = disabled;
    setReadout(
      disabled
        ? "当前模式仅供预览。"
        : "拖动任意控制点，横轴为温度，纵轴为 PWM。",
    );
  }, [disabled]);

  useEffect(() => {
    const chart = chartRef.current;
    if (!chart) return;
    draftRef.current = draft;
    pendingDraftRef.current = draft;
    chart.setOption(curveOption(draft, minPwm), true);

    const frame = window.requestAnimationFrame(() => {
      const values = curveValues(draft, minPwm);
      const graphics = curves.flatMap((curve) =>
        values[curve.key].map((temperature, pointIndex) => {
          const pixel = chart.convertToPixel(
            { xAxisIndex: 0, yAxisIndex: 0 },
            [temperature, values.pwm[pointIndex]],
          ) as number[];
          const move = (position: number[] | undefined, commit: boolean) => {
            if (disabledRef.current || !position) return;
            const data = chart.convertFromPixel(
              { xAxisIndex: 0, yAxisIndex: 0 },
              position,
            ) as number[];
            const next = updateCurvePoint(
              pendingDraftRef.current,
              minPwm,
              curve.key,
              pointIndex,
              Number(data?.[0]),
              Number(data?.[1]),
            );
            pendingDraftRef.current = next.draft;
            chart.setOption(
              { series: curveSeries(next.draft, minPwm) },
              { replaceMerge: ["series"], lazyUpdate: true },
            );
            setReadout(
              `${curve.label} · ${next.temperature} °C · PWM ${next.pwm}`,
            );
            if (commit) {
              draftRef.current = next.draft;
              changeRef.current(next.draft);
            }
          };
          return {
            id: `handle-${curve.key}-${pointIndex}`,
            type: "circle",
            position: pixel,
            shape: { r: 14 },
            style: { fill: "rgba(255,255,255,0.001)" },
            cursor: disabled ? "default" : "move",
            draggable: !disabled,
            z: 100,
            ondrag: function (this: { position?: number[] }) {
              move(this.position, false);
            },
            ondragend: function (this: { position?: number[] }) {
              move(this.position, true);
            },
          };
        }),
      );
      chart.setOption({ graphic: graphics });
    });
    return () => window.cancelAnimationFrame(frame);
  }, [chartRef, disabled, draft, minPwm]);

  return (
    <section className="fan-curve-graph" aria-label="温度 PWM 曲线编辑器">
      <div className="fan-curve-graph-heading">
        <div>
          <span className="section-kicker">DRAGGABLE CURVE</span>
          <h3>温度—PWM 曲线</h3>
          <small>悬停查看数据；自定义模式可拖拽控制点。</small>
        </div>
        <output aria-live="polite">{readout}</output>
      </div>
      <div
        ref={containerRef}
        className="echarts-fan-canvas"
        role="img"
        aria-label="CPU、HDD 与 NVMe 的温度 PWM 可视化曲线"
      />
    </section>
  );
}

function stockPoints(thresholds: string | undefined, pwm: number[]) {
  const temperatures = parseCsv(thresholds || "", 5, [0, 0, 0, 0, 0]);
  return pwm
    .map((value, index) => [temperatures[index + 1], value])
    .filter((point) => point[0] > 0);
}

function sameNumbers(left: number[], right: number[]) {
  return (
    left.length === right.length &&
    left.every((value, index) => value === right[index])
  );
}

export function StockFanCurve({ stock }: { stock: StockFanCurveData | null }) {
  const containerRef = useRef<HTMLDivElement | null>(null);
  const chartRef = useEChart(containerRef, Boolean(stock?.available));

  useEffect(() => {
    const chart = chartRef.current;
    if (!chart || !stock?.available) return;
    const systemPwm = parseCsv(stock.system_pwm || "", 4, [64, 128, 204, 255]);
    const cpuPwm = parseCsv(stock.cpu_pwm || "", 4, systemPwm);
    const sources: Array<{
      id: string;
      label: string;
      thresholds?: string;
      color: string;
      pwm: number[];
      dashed?: boolean;
    }> = [
      {
        id: "stock-cpu-system",
        label: "CPU → 系统 PWM",
        thresholds: stock.cpu,
        color: "#1677ff",
        pwm: systemPwm,
      },
      {
        id: "stock-hdd-system",
        label: "HDD → 系统 PWM",
        thresholds: stock.hdd,
        color: "#e89124",
        pwm: systemPwm,
      },
      {
        id: "stock-ssd-system",
        label: "NVMe → 系统 PWM",
        thresholds: stock.ssd,
        color: "#1b9c68",
        pwm: systemPwm,
      },
    ];
    if (!sameNumbers(systemPwm, cpuPwm))
      sources.push({
        id: "stock-cpu-cpu",
        label: "CPU → CPU PWM",
        thresholds: stock.cpu,
        color: "#7357d8",
        pwm: cpuPwm,
        dashed: true,
      });
    const series: LineSeriesOption[] = sources
      .map((source) => ({
        id: source.id,
        name: source.label,
        type: "line" as const,
        data: stockPoints(source.thresholds, source.pwm),
        smooth: 0.16,
        symbol: "circle",
        symbolSize: 8,
        lineStyle: {
          width: 2.4,
          color: source.color,
          type: source.dashed ? ("dashed" as const) : ("solid" as const),
        },
        itemStyle: {
          color: "#ffffff",
          borderColor: source.color,
          borderWidth: 2,
        },
        emphasis: { focus: "series" as const },
      }))
      .filter((item) => Array.isArray(item.data) && item.data.length > 0);
    const maxTemperature =
      Math.max(
        90,
        ...series.flatMap((item) =>
          Array.isArray(item.data)
            ? item.data.map((point) =>
                Array.isArray(point) ? Number(point[0]) : 0,
              )
            : [],
        ),
      ) + 5;
    const option = curveOption(
      {
        minimum: 40,
        cpu: "",
        hdd: "",
        ssd: "",
        pwm: "",
      },
      40,
      maxTemperature,
    );
    chart.setOption({ ...option, series }, true);
  }, [chartRef, stock]);

  if (!stock?.available)
    return <p className="surface-help">暂未读取到该机型的原厂曲线记录。</p>;
  return (
    <section className="fan-curve-graph" aria-label="原厂温度 PWM 曲线">
      <div className="fan-curve-graph-heading">
        <div>
          <span className="section-kicker">RECOVERED STOCK PROFILE</span>
          <h3>原厂温度—PWM 曲线</h3>
          <small>
            来自 UGREEN-NAS-Hardware 的已恢复曲线；仅供查看，不能拖拽或修改。
          </small>
        </div>
        <output>{stock.profile || "stock"}</output>
      </div>
      <div
        ref={containerRef}
        className="echarts-fan-canvas"
        role="img"
        aria-label="原厂只读温度 PWM 曲线"
      />
    </section>
  );
}

function sampleValue(value: unknown) {
  const numeric = Number(value);
  return Number.isFinite(numeric) && numeric >= 0 ? numeric : null;
}

function timeLabel(seconds: number, range: TelemetryRange) {
  const date = new Date(seconds * 1000);
  if (range === "1m")
    return date.toLocaleTimeString("zh-CN", {
      hour: "2-digit",
      minute: "2-digit",
      second: "2-digit",
      hour12: false,
    });
  if (range === "1h")
    return date.toLocaleTimeString("zh-CN", {
      hour: "2-digit",
      minute: "2-digit",
      hour12: false,
    });
  return date.toLocaleString("zh-CN", {
    month: "2-digit",
    day: "2-digit",
    hour: "2-digit",
    minute: "2-digit",
    hour12: false,
  });
}

function telemetryRefreshMilliseconds(range: TelemetryRange) {
  if (range === "1m") return 10_000;
  if (range === "1h") return 60_000;
  return 1_800_000;
}

function telemetryWindowSeconds(range: TelemetryRange) {
  if (range === "1m") return 60;
  if (range === "1h") return 3_600;
  return 86_400;
}

function normalizeTelemetrySamples(
  history: TelemetrySample[],
  current: TelemetrySample | undefined,
  range: TelemetryRange,
) {
  const latestAt = Math.max(
    Number(current?.at) || 0,
    ...history.map((sample) => Number(sample.at) || 0),
  );
  if (latestAt <= 0) return [];

  const cutoff = latestAt - telemetryWindowSeconds(range);
  const samplesByTimestamp = new Map<number, TelemetrySample>();
  for (const sample of [...history, ...(current ? [current] : [])]) {
    const at = Math.floor(Number(sample.at));
    if (!Number.isFinite(at) || at < cutoff || at > latestAt) continue;
    samplesByTimestamp.set(at, { ...sample, at });
  }
  return [...samplesByTimestamp.values()].sort(
    (left, right) => left.at - right.at,
  );
}

function telemetryOption(
  samples: TelemetrySample[],
  range: TelemetryRange,
): EChartsOption {
  const visibleCurves = telemetryCurves.filter((curve) =>
    samples.some((sample) => sampleValue(sample[curve.key]) !== null),
  );
  const rpmValues = samples.flatMap((sample) =>
    ["cpuRpm", "sysRpm", "sys2Rpm"]
      .map((key) => sampleValue(sample[key as TelemetryKey]))
      .filter((value): value is number => value !== null),
  );
  const rpmMaximum = Math.max(
    1000,
    Math.ceil((Math.max(0, ...rpmValues) + 120) / 200) * 200,
  );
  return {
    animation: false,
    aria: { enabled: true },
    grid: { top: 22, right: 54, bottom: 54, left: 50 },
    legend: {
      bottom: 5,
      icon: "circle",
      itemWidth: 9,
      itemHeight: 9,
      itemGap: 15,
      textStyle: { color: "#5f6f86", fontSize: 10, fontWeight: 700 },
    },
    tooltip: {
      trigger: "axis",
      confine: true,
      axisPointer: {
        type: "cross",
        label: { backgroundColor: "rgba(23, 32, 51, 0.90)" },
      },
      backgroundColor: "rgba(23, 32, 51, 0.94)",
      borderWidth: 0,
      padding: [9, 11],
      textStyle: { color: "#ffffff", fontSize: 11 },
      formatter: (input: unknown) => {
        const items = tooltipParams(input);
        const timestamp = Number(items[0]?.axisValue || 0) / 1000;
        const lines = [timeLabel(timestamp, range)];
        for (const item of items) {
          const value = pairValue(item.value, 1);
          if (!Number.isFinite(value)) continue;
          const unit = String(item.seriesId || "").startsWith("rpm-")
            ? "RPM"
            : "°C";
          lines.push(
            `${item.marker || ""}${item.seriesName || ""}：${Math.round(value)} ${unit}`,
          );
        }
        return lines.join("<br/>");
      },
    },
    xAxis: {
      type: "time",
      min: samples.length ? samples[0].at * 1000 : undefined,
      max: samples.length ? samples[samples.length - 1].at * 1000 : undefined,
      boundaryGap: [0, 0],
      axisLine: { lineStyle: { color: axisLineColor } },
      axisTick: { show: false },
      axisLabel: {
        color: axisTextColor,
        fontSize: 9,
        hideOverlap: true,
        formatter: (value: number) => timeLabel(value / 1000, range),
      },
      splitLine: { show: false },
    },
    yAxis: [
      {
        type: "value",
        min: 20,
        max: 100,
        name: "温度 °C",
        nameTextStyle: { color: axisTextColor, fontSize: 10, fontWeight: 700 },
        axisLine: { show: true, lineStyle: { color: axisLineColor } },
        axisTick: { show: false },
        axisLabel: { color: axisTextColor, fontSize: 9 },
        splitLine: { lineStyle: { color: gridLineColor } },
      },
      {
        type: "value",
        min: 0,
        max: rpmMaximum,
        name: "转速 RPM",
        nameTextStyle: { color: axisTextColor, fontSize: 10, fontWeight: 700 },
        axisLine: { show: true, lineStyle: { color: axisLineColor } },
        axisTick: { show: false },
        axisLabel: { color: axisTextColor, fontSize: 9 },
        splitLine: { show: false },
      },
    ],
    series: visibleCurves.map(
      (curve): LineSeriesOption => ({
        id: `${curve.axis === "rpm" ? "rpm" : "temp"}-${curve.key}`,
        name: curve.label,
        type: "line",
        yAxisIndex: curve.axis === "rpm" ? 1 : 0,
        data: samples.map((sample) => [
          sample.at * 1000,
          sampleValue(sample[curve.key]),
        ]),
        connectNulls: true,
        smooth: 0.22,
        showSymbol: samples.length <= 16,
        symbol: "circle",
        symbolSize: 5,
        lineStyle: {
          width: curve.axis === "rpm" ? 1.9 : 2.3,
          color: curve.color,
          type: curve.axis === "rpm" ? "dashed" : "solid",
        },
        itemStyle: { color: curve.color },
        emphasis: {
          focus: "series",
          lineStyle: { width: curve.axis === "rpm" ? 2.5 : 3 },
        },
      }),
    ),
  };
}

export function FanTelemetryChart({ hidden }: { hidden: boolean }) {
  const containerRef = useRef<HTMLDivElement | null>(null);
  const chartRef = useEChart(containerRef);
  const [range, setRange] = useState<TelemetryRange>("1m");
  const [samples, setSamples] = useState<TelemetrySample[]>([]);
  const [sampleInterval, setSampleInterval] = useState(10);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState("");

  useEffect(() => {
    if (hidden) return;
    let active = true;
    let inFlight = false;
    const readTelemetry = async (showLoading: boolean) => {
      if (inFlight) return;
      inFlight = true;
      if (showLoading) {
        setLoading(true);
        setError("");
      }
      try {
        const data = await api<{
          history?: TelemetrySample[];
          current?: TelemetrySample;
          sample_interval_seconds?: number;
        }>("/bios/telemetry", { query: `range=${range}` });
        if (!active) return;
        setSamples(
          normalizeTelemetrySamples(data.history || [], data.current, range),
        );
        setSampleInterval(
          Math.max(1, Number(data.sample_interval_seconds) || 10),
        );
        setError("");
      } catch (reason) {
        if (active)
          setError(
            reason instanceof Error ? reason.message : "温度历史读取失败",
          );
      } finally {
        inFlight = false;
        if (active && showLoading) setLoading(false);
      }
    };

    void readTelemetry(true);
    const timer = window.setInterval(() => {
      if (!document.hidden) void readTelemetry(false);
    }, telemetryRefreshMilliseconds(range));
    const refreshWhenVisible = () => {
      if (!document.hidden) void readTelemetry(false);
    };
    document.addEventListener("visibilitychange", refreshWhenVisible);
    return () => {
      active = false;
      window.clearInterval(timer);
      document.removeEventListener("visibilitychange", refreshWhenVisible);
    };
  }, [hidden, range]);

  useEffect(() => {
    const chart = chartRef.current;
    if (!chart) return;
    chart.setOption(telemetryOption(samples, range), true);
  }, [chartRef, range, samples]);

  const intervalLabel =
    sampleInterval === 1
      ? "每秒"
      : sampleInterval === 10
        ? "每 10 秒"
        : sampleInterval === 60
          ? "每分钟"
          : sampleInterval === 1800
            ? "每 30 分钟"
            : `每 ${sampleInterval} 秒`;

  return (
    <section className="fan-telemetry" aria-label="温度历史">
      <div className="fan-telemetry-heading">
        <div>
          <span className="section-kicker">TEMPERATURE HISTORY</span>
          <h3>温度历史</h3>
          <small>
            {loading
              ? "正在读取…"
              : error ||
                `${intervalLabel}归档 · 悬停可查看同一时刻的温度与风扇转速。`}
          </small>
        </div>
        <div
          className="fan-telemetry-ranges"
          role="group"
          aria-label="温度历史范围"
        >
          {(
            [
              ["1m", "1 分钟"],
              ["1h", "1 小时"],
              ["24h", "24 小时"],
            ] as const
          ).map(([value, label]) => (
            <button
              key={value}
              type="button"
              className={`fan-telemetry-range${range === value ? " active" : ""}`}
              aria-pressed={range === value}
              onClick={() => setRange(value)}
            >
              {label}
            </button>
          ))}
        </div>
      </div>
      <div className="echarts-fan-frame">
        <div
          ref={containerRef}
          className="echarts-fan-canvas"
          role="img"
          aria-label="CPU、HDD、NVMe 温度与风扇转速历史图"
        />
        {loading ? (
          <div className="fan-telemetry-loading" role="status" aria-live="polite">
            <i className="bi bi-arrow-repeat" aria-hidden="true" />
            <span>正在加载历史数据…</span>
          </div>
        ) : null}
      </div>
    </section>
  );
}
