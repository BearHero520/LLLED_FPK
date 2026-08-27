import { lazy, Suspense, useEffect, useMemo, useState } from "react";
import { api } from "../lib/api";
import { boundedInt } from "../lib/ini";
import type { StockFanCurveData } from "./FanCurveCharts";

const FanCurveEditor = lazy(async () => ({
  default: (await import("./FanCurveCharts")).FanCurveEditor,
}));
const FanTelemetryChart = lazy(async () => ({
  default: (await import("./FanCurveCharts")).FanTelemetryChart,
}));
const StockFanCurve = lazy(async () => ({
  default: (await import("./FanCurveCharts")).StockFanCurve,
}));

type BiosData = Record<string, unknown>;
type FanCurve = Record<string, unknown>;
type Toast = (message: string, type?: "ok" | "err") => void;
type FanMode = "custom" | "fixed" | "stock";
type TemperatureCurveKey = "cpu" | "hdd" | "ssd";

const policyLabels: Record<string, string> = {
  on: "自动开机",
  off: "保持关机",
  last: "恢复断电前状态",
};
const defaultCurve = {
  interval: 10,
  downshift: 60,
  minimum: 64,
  cpu: "50,55,75,80,90",
  hdd: "40,45,50,55,70",
  ssd: "45,50,60,65,70",
  pwm: "64,128,204,255",
  requireStorage: false,
};
const curveStages = ["停转", "启动", "中速", "全速", "安全满速"] as const;

function curveFields(value: string, count: number, fallback: string) {
  const fallbackValues = fallback.split(",");
  const values = value.split(",").map((item) => item.trim()).slice(0, count);
  while (values.length < count) values.push(fallbackValues[values.length] || "0");
  return values;
}

function updateCurveField(
  value: string,
  index: number,
  next: string,
  count: number,
  fallback: string,
  min: number,
  max: number,
) {
  const values = curveFields(value, count, fallback);
  const previous = Number(values[index]);
  values[index] = String(
    boundedInt(next, min, max, Number.isFinite(previous) ? previous : min),
  );
  return values.join(",");
}

function uptime(value: unknown) {
  const total = Math.max(0, Math.floor(Number(value) || 0));
  const days = Math.floor(total / 86400);
  const hours = Math.floor((total % 86400) / 3600);
  const minutes = Math.floor((total % 3600) / 60);
  return days
    ? `${days} 天 ${hours} 小时 ${minutes} 分钟`
    : hours
      ? `${hours} 小时 ${minutes} 分钟`
      : `${minutes} 分钟`;
}
function memory(total: unknown, used: unknown, percent: unknown) {
  const totalMb = Number(total) || 0;
  const usedMb = Number(used) || 0;
  const usedText =
    usedMb >= 1024
      ? `${(usedMb / 1024).toFixed(1)} GB`
      : `${Math.round(usedMb)} MB`;
  const totalText =
    totalMb >= 1024
      ? `${(totalMb / 1024).toFixed(1)} GB`
      : `${Math.round(totalMb)} MB`;
  return `${usedText} / ${totalText}${Number.isFinite(Number(percent)) ? `（${percent}%）` : ""}`;
}

function PolicyChoice({
  checked,
  value,
  title,
  copy,
  icon,
  onChange,
}: {
  checked: boolean;
  value: string;
  title: string;
  copy: string;
  icon: string;
  onChange: (value: string) => void;
}) {
  return (
    <label className={`bios-policy-choice${checked ? " active" : ""}`}>
      <input
        type="radio"
        value={value}
        checked={checked}
        onChange={() => onChange(value)}
      />
      <i className={`bi ${icon}`} aria-hidden="true" />
      <span>
        <strong>{title}</strong>
        <small>{copy}</small>
      </span>
    </label>
  );
}

function NumberField({
  label,
  value,
  min,
  max,
  disabled = false,
  onChange,
}: {
  label: string;
  value: number;
  min: number;
  max: number;
  disabled?: boolean;
  onChange: (value: number) => void;
}) {
  return (
    <label>
      <span>{label}</span>
      <input
        type="number"
        min={min}
        max={max}
        step="1"
        value={value}
        disabled={disabled}
        onChange={(event) =>
          onChange(boundedInt(event.target.value, min, max, value))
        }
      />
    </label>
  );
}

function metric(value: unknown) {
  const numeric = Number(value);
  return Number.isFinite(numeric) && numeric >= 0
    ? String(Math.round(numeric))
    : "—";
}

export function BiosPage({
  hidden,
  bios,
  hardware,
  onRefresh,
  onToast,
}: {
  hidden: boolean;
  bios: BiosData | null;
  hardware: Record<string, unknown>;
  onRefresh: () => Promise<void>;
  onToast: Toast;
}) {
  const [fanCurve, setFanCurve] = useState<FanCurve | null>(null);
  const [mode, setMode] = useState<FanMode>("custom");
  const [curve, setCurve] = useState(defaultCurve);
  const [cpuPwm, setCpuPwm] = useState(120);
  const [sysPwm, setSysPwm] = useState(100);
  const [startup, setStartup] = useState("last");
  const [wol, setWol] = useState("on");
  const [schedule, setSchedule] = useState({
    enabled: false,
    days: new Set<string>(),
    wake: "07:00",
    shutdown: "23:00",
  });
  const [riskAccepted, setRiskAccepted] = useState(false);
  const [busy, setBusy] = useState<string | null>(null);
  const info = bios || {};
  const system = hardware;
  const minPwm = Math.max(40, Number(info.min_pwm) || 40);
  const writeRequired = Boolean(info.write_confirmation_required);
  const writeReady =
    !writeRequired ||
    riskAccepted ||
    Boolean(info.write_confirmation_acknowledged);
  const available = Boolean(info.available);
  const supported = Boolean(info.supported);
  const telemetry = (info.telemetry || {}) as Record<string, unknown>;
  const reportedFanCurve = (info.fan_curve || {}) as FanCurve;
  const effectiveFanCurve = fanCurve || reportedFanCurve;
  const stockCurve = (effectiveFanCurve.stock_curve || {}) as StockFanCurveData;
  const curveEditable = available && writeReady && mode === "custom";

  useEffect(() => {
    if (hidden) return;
    void api<FanCurve>("/bios/fan-curve")
      .then(setFanCurve)
      .catch(() => setFanCurve(null));
  }, [hidden]);
  useEffect(() => {
    if (!bios) return;
    setCpuPwm(boundedInt(info.cpu_pwm as string | number, minPwm, 255, 120));
    setSysPwm(boundedInt(info.sys_pwm as string | number, minPwm, 255, 100));
    setStartup(String(info.startup || "last"));
    setWol(String(info.wol || "on"));
    const remote = (info.power_schedule || {}) as Record<string, unknown>;
    setSchedule({
      enabled: Boolean(remote.enabled),
      days: new Set(
        String(remote.days || "")
          .split(",")
          .filter(Boolean),
      ),
      wake: String(remote.wake_time || "07:00"),
      shutdown: String(remote.shutdown_time || "23:00"),
    });
  }, [
    bios,
    info.cpu_pwm,
    info.power_schedule,
    info.startup,
    info.sys_pwm,
    info.wol,
    minPwm,
  ]);
  useEffect(() => {
    if (!fanCurve) return;
    if (String(fanCurve.profile || "").startsWith("stock-")) setMode("stock");
    setCurve({
      interval: boundedInt(
        fanCurve.interval_seconds as string | number,
        2,
        300,
        defaultCurve.interval,
      ),
      downshift: boundedInt(
        fanCurve.downshift_delay_seconds as string | number,
        0,
        3600,
        defaultCurve.downshift,
      ),
      minimum: boundedInt(
        fanCurve.minimum_pwm as string | number,
        minPwm,
        255,
        defaultCurve.minimum,
      ),
      cpu: String(fanCurve.cpu_curve || defaultCurve.cpu),
      hdd: String(fanCurve.hdd_curve || defaultCurve.hdd),
      ssd: String(fanCurve.ssd_curve || defaultCurve.ssd),
      pwm: String(fanCurve.pwm_curve || defaultCurve.pwm),
      requireStorage: Boolean(fanCurve.require_storage_sensor),
    });
  }, [fanCurve, minPwm]);

  const run = async (name: string, action: () => Promise<void>) => {
    setBusy(name);
    try {
      await action();
    } catch (error) {
      onToast(error instanceof Error ? error.message : "BIOS 操作失败", "err");
    } finally {
      setBusy(null);
    }
  };
  const confirmation = () => (writeReady ? "confirm=firmware-reversed" : "");
  const guarded = async (action: () => Promise<void>) => {
    if (!writeReady) {
      onToast("请先确认受保护 BIOS 写入风险", "err");
      return;
    }
    await action();
  };
  const sync = async (message?: string) => {
    await onRefresh();
    const next = await api<FanCurve>("/bios/fan-curve");
    setFanCurve(next);
    if (message) onToast(message);
  };
  const curveQuery = useMemo(
    () =>
      new URLSearchParams({
        action: "start",
        mode:
          mode === "stock" ? String(stockCurve.profile || "custom") : "custom",
        interval: String(curve.interval),
        downshift: String(curve.downshift),
        minimum: String(curve.minimum),
        cpu: curve.cpu,
        hdd: curve.hdd,
        ssd: curve.ssd,
        pwm: curve.pwm,
        require_storage: curve.requireStorage ? "true" : "false",
        ...(writeReady ? { confirm: "firmware-reversed" } : {}),
      }).toString(),
    [curve, mode, stockCurve.profile, writeReady],
  );
  const toggleDay = (day: string) =>
    setSchedule((current) => {
      const days = new Set(current.days);
      days.has(day) ? days.delete(day) : days.add(day);
      return { ...current, days };
    });

  if (!supported)
    return (
      <section className="react-view" hidden={hidden} aria-label="BIOS 控制">
        <article className="glass-surface bios-status-surface">
          <div className="section-heading">
            <div>
              <span className="section-kicker">MODEL GUARD</span>
              <h2>BIOS 控制不可用</h2>
            </div>
            <span className="soft-badge">非适用机型</span>
          </div>
          <p className="surface-help">
            此入口只对已验证映射的 DXP4800 系列、DXP480T Plus 与 DXP6800 Pro
            开放。当前机型不会执行 BIOS 写入。
          </p>
        </article>
      </section>
    );

  return (
    <section className="react-view" hidden={hidden} aria-label="BIOS 控制">
      <div className="bios-layout">
        <div className="bios-controller-row">
          <article className="glass-surface bios-status-surface">
          <div className="section-heading">
            <div>
              <span className="section-kicker">
                {String(info.model || "SUPPORTED MODEL").toUpperCase()} · IT8613
              </span>
              <h2>BIOS 控制器</h2>
            </div>
            <span className="soft-badge">
              {available
                ? "风扇 hwmon 就绪"
                : info.startup_available
                  ? "仅来电启动就绪"
                  : "控制器不可用"}
            </span>
          </div>
          <p className="surface-help" role="status">
            {available
              ? "已检测到可用控制接口。写入由 UGREEN-NAS-Hardware 负责，所有变更都会进行保护和回读校验。"
              : String(
                  info.fan_error ||
                    info.error ||
                    "没有找到可用的 BIOS 控制接口。",
                )}
          </p>
          <div className="bios-facts">
            <span>
              <small>设备型号</small>
              <strong>{String(info.product_name || "未读取到")}</strong>
            </span>
            <span>
              <small>控制芯片</small>
              <strong>
                {info.chip_id
                  ? `${String(info.chip_id)} · Rev ${String(info.revision ?? 0)}`
                  : "未读取"}
              </strong>
            </span>
            <span>
              <small>访问后端</small>
              <strong>
                {String(
                  info.backend === "ugreenctl"
                    ? "UGREEN-NAS-Hardware"
                    : info.backend || "不可用",
                )}
              </strong>
            </span>
            <span>
              <small>来电启动</small>
              <strong>{policyLabels[String(info.startup)] || "不可用"}</strong>
            </span>
          </div>
          </article>
          <aside className="glass-surface bios-detail-surface">
            <span className="bios-detail-icon">
              <i className="bi bi-shield-check" aria-hidden="true" />
            </span>
            <div>
              <span className="section-kicker">MODEL GUARD</span>
              <h2>支持机型保护</h2>
              <p>
                写入仅由 UGREEN-NAS-Hardware
                在模型、芯片、锁与回读校验均通过时执行。前端不会直接访问寄存器或硬件接口。
              </p>
              {writeRequired &&
              !riskAccepted &&
              !info.write_confirmation_acknowledged ? (
                <label className="bios-experimental-confirm">
                  <input
                    type="checkbox"
                    checked={riskAccepted}
                    onChange={(event) => {
                      const next = event.target.checked;
                      setRiskAccepted(next);
                      if (next)
                        void api<{
                          write_confirmation_acknowledged?: boolean;
                        }>("/bios/confirmation", {
                          method: "POST",
                          query: "confirm=firmware-reversed",
                          body: "",
                        })
                          .then((data) => {
                            setRiskAccepted(
                              Boolean(data.write_confirmation_acknowledged),
                            );
                            onToast("已确认受保护写入风险");
                          })
                          .catch((error) => {
                            setRiskAccepted(false);
                            onToast(
                              error instanceof Error
                                ? error.message
                                : "无法确认写入风险",
                              "err",
                            );
                          });
                    }}
                  />
                  <span>
                    <strong>我已了解固件逆向写入风险</strong>
                    <small>已准备独立温度监控与恢复原厂控制的方案。</small>
                  </span>
                </label>
              ) : (
                <p className="surface-help">
                  {writeReady
                    ? "受保护写入已确认。"
                    : "当前机型不需要额外写入确认。"}
                </p>
              )}
            </div>
          </aside>
        </div>
        <article className="glass-surface bios-system-surface">
          <div className="section-heading">
            <div>
              <span className="section-kicker">SYSTEM TELEMETRY</span>
              <h2>系统信息</h2>
            </div>
            <span className="soft-badge">实时只读</span>
          </div>
          <p className="surface-help">
            来自 Linux 系统接口的只读信息，每次刷新页面状态时同步更新。
          </p>
          <div className="bios-system-grid">
            <div className="bios-system-fact">
              <small>
                <i className="bi bi-pc-display-horizontal" aria-hidden="true" />
                主机名
              </small>
              <strong>{String(system.system_hostname || "未读取到")}</strong>
            </div>
            <div className="bios-system-fact">
              <small>
                <i className="bi bi-box" aria-hidden="true" />
                系统版本
              </small>
              <strong>{String(system.system_os || "未读取到")}</strong>
            </div>
            <div className="bios-system-fact">
              <small>
                <i className="bi bi-terminal" aria-hidden="true" />
                内核版本
              </small>
              <strong>{String(system.kernel || "未读取到")}</strong>
            </div>
            <div className="bios-system-fact">
              <small>
                <i className="bi bi-clock-history" aria-hidden="true" />
                运行时间
              </small>
              <strong>{uptime(system.system_uptime_seconds)}</strong>
            </div>
            <div className="bios-system-fact wide">
              <small>
                <i className="bi bi-cpu" aria-hidden="true" />
                处理器
              </small>
              <strong>{String(system.system_cpu_model || "未读取到")}</strong>
            </div>
            <div className="bios-system-fact">
              <small>
                <i className="bi bi-diagram-3" aria-hidden="true" />
                逻辑线程
              </small>
              <strong>{String(system.system_cpu_threads || "—")} 线程</strong>
            </div>
            <div className="bios-system-fact">
              <small>
                <i className="bi bi-thermometer-half" aria-hidden="true" />
                CPU 温度
              </small>
              <strong>
                {Number(system.system_cpu_temp_c)
                  ? `${system.system_cpu_temp_c} °C`
                  : "—"}
              </strong>
            </div>
            <div className="bios-system-fact wide">
              <small>
                <i className="bi bi-memory" aria-hidden="true" />
                内存使用
              </small>
              <strong>
                {memory(
                  system.system_memory_total_mb,
                  system.system_memory_used_mb,
                  system.system_memory_percent,
                )}
              </strong>
            </div>
            <div className="bios-system-fact wide">
              <small>
                <i className="bi bi-speedometer2" aria-hidden="true" />
                系统负载（1 / 5 / 15 分钟）
              </small>
              <strong>
                {[
                  system.system_load_1,
                  system.system_load_5,
                  system.system_load_15,
                ]
                  .map((value) => Number(value || 0).toFixed(2))
                  .join(" / ")}
              </strong>
            </div>
          </div>
        </article>
        <article className="glass-surface fan-curve-surface">
          <div className="section-heading">
            <div>
              <span className="section-kicker">FAN OPERATION MODE</span>
              <h2>风扇运行模式</h2>
            </div>
            <span className="soft-badge">
              {fanCurve?.running
                ? "自动温控运行中"
                : mode === "fixed"
                  ? "固定转速"
                  : "未启动"}
            </span>
          </div>
          <p className="surface-help">
            风扇控制通过受保护的硬件服务完成。固定转速不看温度；两种自动模式按下方温度—PWM
            参数调速。
          </p>
          <div className="fan-curve-live">
            <div>
              <span>CPU</span>
              <strong>{metric(telemetry.cpu)}</strong>
              <small>°C</small>
            </div>
            <div>
              <span>HDD</span>
              <strong>{metric(telemetry.hdd)}</strong>
              <small>°C</small>
            </div>
            <div>
              <span>NVMe</span>
              <strong>{metric(telemetry.ssd)}</strong>
              <small>°C</small>
            </div>
            <div>
              <span>目标 PWM</span>
              <strong>{metric(effectiveFanCurve.desired_pwm)}</strong>
              <small>{effectiveFanCurve.running ? "自动调速" : "未写入"}</small>
            </div>
            <div>
              <span>CPU 目标 PWM</span>
              <strong>
                {metric(
                  effectiveFanCurve.desired_cpu_pwm ??
                    effectiveFanCurve.desired_pwm,
                )}
              </strong>
              <small>{effectiveFanCurve.running ? "曲线目标" : "未写入"}</small>
            </div>
            <div>
              <span>系统目标 PWM</span>
              <strong>
                {metric(
                  effectiveFanCurve.desired_system_pwm ??
                    effectiveFanCurve.desired_pwm,
                )}
              </strong>
              <small>{effectiveFanCurve.running ? "曲线目标" : "未写入"}</small>
            </div>
            <div>
              <span>CPU 风扇</span>
              <strong>{metric(telemetry.cpuRpm ?? info.cpu_rpm)}</strong>
              <small>RPM</small>
            </div>
            <div>
              <span>系统风扇</span>
              <strong>{metric(telemetry.sysRpm ?? info.sys_rpm)}</strong>
              <small>RPM</small>
            </div>
            {Number(telemetry.sys2Rpm ?? info.sys2_rpm) >= 0 ? (
              <div>
                <span>系统风扇 2</span>
                <strong>{metric(telemetry.sys2Rpm ?? info.sys2_rpm)}</strong>
                <small>RPM</small>
              </div>
            ) : null}
          </div>
          {!hidden ? (
            <Suspense fallback={null}>
              <FanTelemetryChart hidden={hidden} />
            </Suspense>
          ) : null}
          <fieldset className="fan-curve-mode-group">
            <legend>选择运行模式</legend>
            <label
              className={`bios-policy-choice${mode === "stock" ? " active" : ""}`}
            >
              <input
                type="radio"
                name="reactFanMode"
                checked={mode === "stock"}
                onChange={() => setMode("stock")}
              />
              <span>
                <strong>原厂兼容自动</strong>
                <small>使用已恢复机型的安全温度—PWM 参数。</small>
              </span>
            </label>
            <label
              className={`bios-policy-choice${mode === "custom" ? " active" : ""}`}
            >
              <input
                type="radio"
                name="reactFanMode"
                checked={mode === "custom"}
                onChange={() => setMode("custom")}
              />
              <span>
                <strong>自定义自动</strong>
                <small>按下方曲线参数自动调速。</small>
              </span>
            </label>
            <label
              className={`bios-policy-choice${mode === "fixed" ? " active" : ""}`}
            >
              <input
                type="radio"
                name="reactFanMode"
                checked={mode === "fixed"}
                onChange={() => setMode("fixed")}
              />
              <span>
                <strong>固定转速</strong>
                <small>不看温度，按指定 PWM 持续运行。</small>
              </span>
            </label>
          </fieldset>
          {mode === "fixed" ? (
            <section className="fan-fixed-settings">
              <div className="section-heading">
                <div>
                  <span className="section-kicker">FIXED FAN SPEED</span>
                  <h3>固定转速设置</h3>
                </div>
                <span className="soft-badge">{minPwm}–255</span>
              </div>
              <div className="bios-safety-note" role="note">
                <i className="bi bi-exclamation-triangle" aria-hidden="true" />
                <p>
                  固定转速不会按温度变化。应用固定转速会先停止自动温控，并要求已确认写入风险。
                </p>
              </div>
              <div className="bios-fan-grid">
                <section className="bios-fan-card">
                  <div className="bios-fan-head">
                    <span className="bios-fan-icon">
                      <i className="bi bi-cpu" aria-hidden="true" />
                    </span>
                    <div>
                      <small>CPU FAN</small>
                      <strong>CPU 风扇</strong>
                    </div>
                    <span className="bios-rpm">
                      <strong>{String(info.cpu_rpm ?? "—")}</strong>
                      <small>RPM</small>
                    </span>
                  </div>
                  <div className="bios-control-state">
                    <span>当前 PWM</span>
                    <strong>{String(info.cpu_pwm ?? "—")}</strong>
                    <small>最低 {minPwm}</small>
                  </div>
                  <div className="bios-pwm-control">
                    <input
                      type="range"
                      min={minPwm}
                      max="255"
                      value={cpuPwm}
                      disabled={!writeReady || info.cpu_fan_present === false}
                      onChange={(event) =>
                        setCpuPwm(
                          boundedInt(event.target.value, minPwm, 255, cpuPwm),
                        )
                      }
                    />
                  </div>
                  <div className="bios-fan-write-status">
                    <i className="bi bi-lightning-charge" aria-hidden="true" />
                    <span>PWM {cpuPwm}</span>
                  </div>
                </section>
                <section className="bios-fan-card">
                  <div className="bios-fan-head">
                    <span className="bios-fan-icon">
                      <i className="bi bi-fan" aria-hidden="true" />
                    </span>
                    <div>
                      <small>SYSTEM FAN</small>
                      <strong>
                        系统风扇
                        {info.fan_write_target === "all" ? "（成对）" : ""}
                      </strong>
                    </div>
                    <span className="bios-rpm">
                      <strong>{String(info.sys_rpm ?? "—")}</strong>
                      <small>RPM</small>
                    </span>
                  </div>
                  <div className="bios-control-state">
                    <span>当前 PWM</span>
                    <strong>{String(info.sys_pwm ?? "—")}</strong>
                    <small>最低 {minPwm}</small>
                  </div>
                  <div className="bios-pwm-control">
                    <input
                      type="range"
                      min={minPwm}
                      max="255"
                      value={sysPwm}
                      disabled={!writeReady}
                      onChange={(event) =>
                        setSysPwm(
                          boundedInt(event.target.value, minPwm, 255, sysPwm),
                        )
                      }
                    />
                  </div>
                  <div className="bios-fan-write-status">
                    <i className="bi bi-lightning-charge" aria-hidden="true" />
                    <span>PWM {sysPwm}</span>
                  </div>
                </section>
              </div>
              <div className="fan-curve-actions">
                <span className="fan-curve-status">
                  {writeReady
                    ? "可应用固定 PWM；会停止自动温控并回读校验。"
                    : "请先确认 BIOS 写入风险。"}
                </span>
                <div>
                  <button
                    type="button"
                    className="primary-button"
                    disabled={busy === "fixed" || !writeReady}
                    onClick={() =>
                      void run("fixed", () =>
                        guarded(async () => {
                          if (fanCurve?.running)
                            await api("/bios/fan-curve", {
                              method: "POST",
                              query: `action=stop&${confirmation()}`,
                              body: "",
                            });
                          if (info.cpu_fan_present !== false)
                            await api("/bios/fan", {
                              method: "POST",
                              query: `channel=cpu&pwm=${cpuPwm}&${confirmation()}`,
                              body: "",
                            });
                          await api("/bios/fan", {
                            method: "POST",
                            query: `channel=${info.fan_write_target === "all" ? "all" : "sys"}&pwm=${sysPwm}&${confirmation()}`,
                            body: "",
                          });
                          await sync("固定转速已应用");
                        }),
                      )
                    }
                  >
                    <i className="bi bi-check2-circle" aria-hidden="true" />
                    应用固定转速
                  </button>
                </div>
              </div>
            </section>
          ) : mode === "stock" ? (
            <section className="fan-curve-settings">
              {!hidden ? (
                <Suspense fallback={null}>
                  <StockFanCurve stock={stockCurve} />
                </Suspense>
              ) : null}
              <div className="fan-curve-actions">
                <span className="fan-curve-status">
                  {effectiveFanCurve.running
                    ? "原厂自动温控正在运行。"
                    : "将按当前机型的原厂恢复曲线启动自动温控。"}
                </span>
                <div>
                  <button
                    type="button"
                    className="secondary-button"
                    disabled={busy === "stop" || !effectiveFanCurve.running}
                    onClick={() =>
                      void run("stop", () =>
                        guarded(async () => {
                          await api("/bios/fan-curve", {
                            method: "POST",
                            query: `action=stop&${confirmation()}`,
                            body: "",
                          });
                          await sync("原厂自动温控已停止");
                        }),
                      )
                    }
                  >
                    <i className="bi bi-stop-circle" aria-hidden="true" />
                    停止自动温控
                  </button>
                  <button
                    type="button"
                    className="primary-button"
                    disabled={
                      busy === "curve" || !writeReady || !stockCurve.available
                    }
                    onClick={() =>
                      void run("curve", () =>
                        guarded(async () => {
                          await api("/bios/fan-curve", {
                            method: "POST",
                            query: curveQuery,
                            body: "",
                          });
                          await sync("原厂自动温控已启动");
                        }),
                      )
                    }
                  >
                    <i className="bi bi-play-circle" aria-hidden="true" />
                    按原厂曲线启动
                  </button>
                </div>
              </div>
            </section>
          ) : (
            <section className="fan-curve-settings">
              <div className="fan-curve-timing">
                <NumberField
                  label="检测间隔"
                  min={2}
                  max={300}
                  value={curve.interval}
                  disabled={!curveEditable}
                  onChange={(value) =>
                    setCurve((current) => ({ ...current, interval: value }))
                  }
                />
                <NumberField
                  label="降速保持"
                  min={0}
                  max={3600}
                  value={curve.downshift}
                  disabled={!curveEditable}
                  onChange={(value) =>
                    setCurve((current) => ({ ...current, downshift: value }))
                  }
                />
                <NumberField
                  label="最低 PWM"
                  min={minPwm}
                  max={255}
                  value={curve.minimum}
                  disabled={!curveEditable}
                  onChange={(value) =>
                    setCurve((current) => ({ ...current, minimum: value }))
                  }
                />
              </div>
              {!hidden ? (
                <Suspense fallback={null}>
                  <FanCurveEditor
                    draft={curve}
                    minPwm={minPwm}
                    disabled={!curveEditable}
                    onChange={(next) =>
                      setCurve((current) => ({ ...current, ...next }))
                    }
                  />
                </Suspense>
              ) : null}
              <div className="fan-curve-table-wrap">
                <table className="fan-curve-table">
                  <thead>
                    <tr>
                      <th>温度源</th>
                      {curveStages.map((stage) => <th key={stage}>{stage}</th>)}
                    </tr>
                  </thead>
                  <tbody>
                    {(
                      [
                        ["CPU", "cpu"],
                        ["HDD", "hdd"],
                        ["NVMe", "ssd"],
                      ] as const
                    ).map(([label, key]) => (
                      <tr key={key}>
                        <th>{label}</th>
                        {curveFields(curve[key], 5, defaultCurve[key]).map((value, index) => (
                          <td key={`${key}-${curveStages[index]}`}>
                            <label className="curve-stage-input">
                              <input
                                type="number"
                                min="0"
                                max="120"
                                step="1"
                                value={value}
                                aria-label={`${label} ${curveStages[index]}温度`}
                                disabled={!curveEditable}
                                onChange={(event) =>
                                  setCurve((current) => ({
                                    ...current,
                                    [key]: updateCurveField(
                                      current[key],
                                      index,
                                      event.target.value,
                                      5,
                                      defaultCurve[key],
                                      0,
                                      120,
                                    ),
                                  }))
                                }
                              />
                              <span>°C</span>
                            </label>
                          </td>
                        ))}
                      </tr>
                    ))}
                    <tr className="fan-curve-pwm-row">
                      <th>PWM 档位</th>
                      <td className="curve-stage-unused" aria-label="停转阶段不写入 PWM">—</td>
                      {curveFields(curve.pwm, 4, defaultCurve.pwm).map((value, index) => (
                        <td key={`pwm-${curveStages[index + 1]}`}>
                          <label className="curve-stage-input">
                            <input
                              type="number"
                              min={minPwm}
                              max="255"
                              step="1"
                              value={value}
                              aria-label={`${curveStages[index + 1]} PWM`}
                              disabled={!curveEditable}
                              onChange={(event) =>
                                setCurve((current) => ({
                                  ...current,
                                  pwm: updateCurveField(
                                    current.pwm,
                                    index,
                                    event.target.value,
                                    4,
                                    defaultCurve.pwm,
                                    minPwm,
                                    255,
                                  ),
                                }))
                              }
                            />
                          </label>
                        </td>
                      ))}
                    </tr>
                  </tbody>
                </table>
              </div>
              <label className="fan-curve-storage-check">
                <input
                  type="checkbox"
                  checked={curve.requireStorage}
                  disabled={!curveEditable}
                  onChange={(event) =>
                    setCurve((current) => ({
                      ...current,
                      requireStorage: event.target.checked,
                    }))
                  }
                />
                <span>
                  <strong>存储温度缺失时保护性满速</strong>
                  <small>
                    开启后，未读取到任意 HDD/NVMe 温度时会写入 PWM 255。
                  </small>
                </span>
              </label>
              <div className="fan-curve-actions">
                <span className="fan-curve-status">
                  {fanCurve?.running
                    ? "自动温控正在运行。"
                    : "尚未启用自动温控。"}
                </span>
                <div>
                  <button
                    type="button"
                    className="secondary-button"
                    disabled={busy === "stop" || !fanCurve?.running}
                    onClick={() =>
                      void run("stop", () =>
                        guarded(async () => {
                          await api("/bios/fan-curve", {
                            method: "POST",
                            query: `action=stop&${confirmation()}`,
                            body: "",
                          });
                          await sync("自动温控已停止");
                        }),
                      )
                    }
                  >
                    <i className="bi bi-stop-circle" aria-hidden="true" />
                    停止自动温控
                  </button>
                  <button
                    type="button"
                    className="primary-button"
                    disabled={busy === "curve" || !writeReady}
                    onClick={() =>
                      void run("curve", () =>
                        guarded(async () => {
                          await api("/bios/fan-curve", {
                            method: "POST",
                            query: curveQuery,
                            body: "",
                          });
                          await sync("自动温控曲线已启动");
                        }),
                      )
                    }
                  >
                    <i className="bi bi-play-circle" aria-hidden="true" />
                    应用并启动自动
                  </button>
                </div>
              </div>
            </section>
          )}
        </article>
        <div className="bios-card-waterfall">
          <div className="bios-card-column">
            <article className="glass-surface bios-startup-surface">
              <div className="section-heading">
                <div>
                  <span className="section-kicker">AC POWER RECOVERY</span>
                  <h2>来电启动策略</h2>
                </div>
                <span className="soft-badge">
                  {policyLabels[String(info.startup)] || "不可用"}
                </span>
              </div>
              <p className="surface-help">
                设置交流电恢复后设备的启动行为。该能力由 UGREEN-NAS-Hardware
                单独保护。
              </p>
              <div
                className="bios-policy-grid"
                role="radiogroup"
                aria-label="来电启动策略"
              >
                <PolicyChoice
                  checked={startup === "on"}
                  value="on"
                  title="自动开机"
                  copy="供电恢复后立即启动"
                  icon="bi-power"
                  onChange={setStartup}
                />
                <PolicyChoice
                  checked={startup === "off"}
                  value="off"
                  title="保持关机"
                  copy="供电恢复后等待手动开机"
                  icon="bi-moon"
                  onChange={setStartup}
                />
                <PolicyChoice
                  checked={startup === "last"}
                  value="last"
                  title="恢复断电前状态"
                  copy="按断电前状态恢复"
                  icon="bi-arrow-repeat"
                  onChange={setStartup}
                />
              </div>
              <div className="bios-startup-actions">
                <button
                  type="button"
                  className="primary-button"
                  disabled={
                    busy === "startup" || !info.startup_available || !writeReady
                  }
                  onClick={() =>
                    void run("startup", () =>
                      guarded(async () => {
                        await api("/bios/startup", {
                          method: "POST",
                          query: `policy=${startup}&${confirmation()}`,
                          body: "",
                        });
                        await sync("来电启动策略已更新");
                      }),
                    )
                  }
                >
                  <i className="bi bi-floppy" aria-hidden="true" />
                  保存来电启动策略
                </button>
              </div>
            </article>
            {Boolean(
              (info.power_schedule as Record<string, unknown> | undefined)
                ?.available,
            ) ? (
              <article className="glass-surface bios-startup-surface">
                <div className="section-heading">
                  <div>
                    <span className="section-kicker">SCHEDULED POWER</span>
                    <h2>定时开关机</h2>
                  </div>
                  <span className="soft-badge">
                    {schedule.enabled ? "已启用" : "已关闭"}
                  </span>
                </div>
                <p className="surface-help">
                  定时关机前会设置下一次 RTC 唤醒，然后调用系统安全关机。
                </p>
                <div className="bios-policy-grid">
                  <label
                    className={`bios-policy-choice${schedule.enabled ? " active" : ""}`}
                  >
                    <input
                      type="checkbox"
                      checked={schedule.enabled}
                      onChange={(event) =>
                        setSchedule((current) => ({
                          ...current,
                          enabled: event.target.checked,
                        }))
                      }
                    />
                    <i className="bi bi-calendar2-check" aria-hidden="true" />
                    <span>
                      <strong>启用定时开关机</strong>
                      <small>未启用时会移除计划并清除 RTC 唤醒。</small>
                    </span>
                  </label>
                  <label className="bios-policy-choice">
                    <i className="bi bi-clock-history" aria-hidden="true" />
                    <span>
                      <strong>定时开机</strong>
                      <small>
                        <input
                          className="bios-schedule-time"
                          type="time"
                          value={schedule.wake}
                          onChange={(event) =>
                            setSchedule((current) => ({
                              ...current,
                              wake: event.target.value,
                            }))
                          }
                        />
                      </small>
                    </span>
                  </label>
                  <label className="bios-policy-choice">
                    <i className="bi bi-power" aria-hidden="true" />
                    <span>
                      <strong>定时关机</strong>
                      <small>
                        <input
                          className="bios-schedule-time"
                          type="time"
                          value={schedule.shutdown}
                          onChange={(event) =>
                            setSchedule((current) => ({
                              ...current,
                              shutdown: event.target.value,
                            }))
                          }
                        />
                      </small>
                    </span>
                  </label>
                </div>
                <div className="bios-policy-grid">
                  {[
                    ["1", "周一"],
                    ["2", "周二"],
                    ["3", "周三"],
                    ["4", "周四"],
                    ["5", "周五"],
                    ["6", "周六"],
                    ["7", "周日"],
                  ].map(([day, label]) => (
                    <label
                      key={day}
                      className={`bios-policy-choice${schedule.days.has(day) ? " active" : ""}`}
                    >
                      <input
                        type="checkbox"
                        checked={schedule.days.has(day)}
                        onChange={() => toggleDay(day)}
                      />
                      <span>
                        <strong>{label}</strong>
                        <small>重复执行</small>
                      </span>
                    </label>
                  ))}
                </div>
                <div className="bios-startup-actions">
                  <button
                    type="button"
                    className="primary-button"
                    disabled={busy === "schedule" || !writeReady}
                    onClick={() =>
                      void run("schedule", () =>
                        guarded(async () => {
                          if (
                            schedule.enabled &&
                            (!schedule.days.size ||
                              !schedule.wake ||
                              !schedule.shutdown)
                          )
                            throw new Error(
                              "启用定时开关机前，请选择重复日期、开机时间和关机时间",
                            );
                          const query = new URLSearchParams({
                            enabled: String(schedule.enabled),
                            days: [...schedule.days].sort().join(","),
                            wake_time: schedule.wake,
                            shutdown_time: schedule.shutdown,
                            ...(writeReady
                              ? { confirm: "firmware-reversed" }
                              : {}),
                          }).toString();
                          await api("/bios/power-schedule", {
                            method: "POST",
                            query,
                            body: "",
                          });
                          await sync("定时开关机计划已更新");
                        }),
                      )
                    }
                  >
                    <i className="bi bi-calendar2-check" aria-hidden="true" />
                    保存定时开关机计划
                  </button>
                </div>
              </article>
            ) : null}
          </div>
          <div className="bios-card-column">
            <article className="glass-surface bios-startup-surface">
              <div className="section-heading">
                <div>
                  <span className="section-kicker">WAKE-ON-LAN</span>
                  <h2>网络唤醒</h2>
                </div>
                <span className="soft-badge">
                  {info.wol_available
                    ? String(info.wol) === "on"
                      ? "已启用"
                      : "已关闭"
                    : "不可用"}
                </span>
              </div>
              <p className="surface-help">
                网络唤醒会按经过验证的网卡拓扑配置魔术包唤醒并回读确认。
              </p>
              <div
                className="bios-policy-grid"
                role="radiogroup"
                aria-label="网络唤醒策略"
              >
                <PolicyChoice
                  checked={wol === "on"}
                  value="on"
                  title="允许魔术包唤醒"
                  copy="关机后接收网卡魔术包启动设备"
                  icon="bi-broadcast-pin"
                  onChange={setWol}
                />
                <PolicyChoice
                  checked={wol === "off"}
                  value="off"
                  title="关闭网络唤醒"
                  copy="禁用板载网口的魔术包唤醒"
                  icon="bi-broadcast"
                  onChange={setWol}
                />
              </div>
              <div className="bios-startup-actions">
                <button
                  type="button"
                  className="primary-button"
                  disabled={
                    busy === "wol" || !info.wol_available || !writeReady
                  }
                  onClick={() =>
                    void run("wol", () =>
                      guarded(async () => {
                        await api("/bios/wol", {
                          method: "POST",
                          query: `policy=${wol}&${confirmation()}`,
                          body: "",
                        });
                        await sync("网络唤醒策略已更新");
                      }),
                    )
                  }
                >
                  <i className="bi bi-floppy" aria-hidden="true" />
                  保存网络唤醒策略
                </button>
              </div>
            </article>
          </div>
        </div>
      </div>
    </section>
  );
}
