// Diagnostics console — reference layout: a left "System Status / Asset
// Summary" rail (col-span-3 on lg) sits beside the primary diagnostics column
// (col-span-9). The primary column hosts a hero import/export chart with an
// inline grid summary, a dense 4-tile telemetry strip, then an 8/4 lower row
// (7-day solar bars + AC voltage spark / inverter snapshot). Below the bento
// the page keeps the existing two-up (today pie + live topology) and a today
// metric strip. All values come from `SiteDiagnostics`; nothing is invented.

import StatTile from "./StatTile.jsx";
import ImportExportChart from "./ImportExportChart.jsx";
import ImportExportPie from "./ImportExportPie.jsx";
import EnergyFlowPanel from "./EnergyFlowPanel.jsx";
import Solar7DayChart from "./Solar7DayChart.jsx";
import AcVoltageSpark from "../dashboard/AcVoltageSpark.jsx";
import { fahrenheitFromCelsius } from "../lib/temperature.js";

const STATUS_TONE = {
  normal:   { ring: "ring-green-500/30", chip: "bg-green-50 text-green-700",   dot: "bg-green-500",   label: "Normal" },
  warn:     { ring: "ring-amber-500/30", chip: "bg-amber-50 text-amber-700",   dot: "bg-amber-500",   label: "Warning" },
  critical: { ring: "ring-red-500/30",   chip: "bg-red-50 text-red-700",       dot: "bg-red-500",     label: "Critical" },
  unknown:  { ring: "ring-outline-variant", chip: "bg-surface-container-high text-on-surface-variant", dot: "bg-on-surface-variant", label: "No telemetry" }
};

export default function DiagnosticsPage({ payload }) {
  const today = payload.today || {};
  const todayPie = payload.today_pie || {};
  const energyFlow = payload.energy_flow || {};
  const latest = payload.latest || {};
  const week = payload.last_7_days || {};
  const ieSeries = payload.import_export_series || [];
  const solarSeries = payload.solar_7d_series || [];

  const todaySolarKwh = round1((todayPie.exported_kwh || 0) + (todayPie.self_consumption_kwh || 0));
  const peakKw = peakAbsKw(ieSeries);

  return (
    <div className="dashboard-reveal flex w-full min-w-0 max-w-full flex-col gap-lg">
      {/* Reference structure: 3/9 rail + main on lg, single-column on mobile. */}
      <div className="grid w-full min-w-0 grid-cols-1 items-start gap-md lg:grid-cols-12">
        <aside className="flex w-full min-w-0 flex-col gap-md lg:col-span-3" aria-label="Diagnostics status rail">
          <SystemStatusCard latest={latest} flow={energyFlow} />
          <AssetSummaryCard week={week} todaySolarKwh={todaySolarKwh} latest={latest} />
        </aside>

        <div className="flex w-full min-w-0 flex-col gap-md lg:col-span-9">
          <HeroChart
            ieSeries={ieSeries}
            flow={energyFlow}
            peakKw={peakKw}
          />
          <ModularTileStrip latest={latest} todaySolarKwh={todaySolarKwh} />
          <LowerRow solarSeries={solarSeries} ieSeries={ieSeries} latest={latest} />
        </div>
      </div>

      {/* Existing real-data panels — kept as supporting content below the bento. */}
      <div className="grid w-full min-w-0 grid-cols-1 items-stretch gap-lg lg:grid-cols-2">
        <Card title="Import / export today" subtitle="Self-use vs grid (integrated kWh)" className="min-w-0">
          <ImportExportPie pie={todayPie} />
        </Card>
        <Card title="Live energy topology" subtitle="Directed flows from the latest snapshot" className="min-w-0">
          <EnergyFlowPanel flow={energyFlow} />
        </Card>
      </div>

      <div className="grid w-full min-w-0 grid-cols-1 items-stretch gap-md sm:grid-cols-2 lg:grid-cols-4">
        <StatTile
          label="Self consumption today"
          value={today.self_consumption_kwh}
          unit="kWh"
          tone="primary"
        />
        <StatTile
          label="Grid consumption today"
          value={today.grid_consumption_kwh}
          unit="kWh"
          tone="error"
        />
        <StatTile label="Consumed today" value={today.consumed_kwh} unit="kWh" tone="error" />
        <StatTile
          label="Inverter temperature"
          value={today.inverter_temp_f ?? fahrenheitFromCelsius(today.inverter_temp_c)}
          unit="°F"
          tone={inverterTempTone(today.inverter_temp_c)}
        />
      </div>
    </div>
  );
}

// ── Left rail ─────────────────────────────────────────────────────────────

function SystemStatusCard({ latest, flow }) {
  const state = latest?.alarm_state ?? (latest?.recorded_at ? "normal" : "unknown");
  const tone = STATUS_TONE[state] || STATUS_TONE.unknown;
  const stateLabel = tone.label;

  return (
    <section
      className="w-full min-w-0 rounded-xl border border-outline-variant bg-surface-container-lowest p-md shadow-sm"
      aria-label="System status"
    >
      <div className="flex items-center justify-between mb-sm">
        <span className="text-label-sm font-semibold uppercase tracking-wide text-on-surface-variant">
          System status
        </span>
        <span className={`inline-flex h-2 w-2 rounded-full ${tone.dot}`} aria-hidden />
      </div>

      <div className={`rounded-xl border border-outline-variant/60 ${tone.chip} px-md py-md text-center ring-1 ${tone.ring}`}>
        <span className="font-[family-name:var(--font-display-serif)] text-display-md tracking-tight">
          {stateLabel}
        </span>
        <p className="text-label-sm uppercase tracking-widest mt-xs">
          {state === "unknown" ? "Awaiting telemetry" : "Latest reported state"}
        </p>
      </div>

      <dl className="mt-md flex flex-col gap-xs text-label-sm">
        <Row label="Grid direction" value={gridDirectionLabel(flow)} />
        <Row label="Inverter status" value={titleize(latest?.inverter_status)} />
        <Row label="Latest sample" value={formatRelative(latest?.recorded_at)} />
      </dl>
    </section>
  );
}

function AssetSummaryCard({ week, todaySolarKwh, latest }) {
  return (
    <section
      className="w-full min-w-0 rounded-xl border border-outline-variant bg-surface-container-lowest p-md shadow-sm"
      aria-label="Asset summary"
    >
      <span className="text-label-sm font-semibold uppercase tracking-wide text-on-surface-variant block mb-sm">
        Asset summary
      </span>

      <div className="flex flex-col gap-md">
        <Stat
          label="Solar today"
          value={todaySolarKwh != null ? todaySolarKwh.toFixed(1) : "—"}
          unit="kWh"
        />
        <Stat
          label="Last 7 days export"
          value={week?.export_kwh != null ? Number(week.export_kwh).toFixed(1) : "—"}
          unit="kWh"
          accent="primary"
          divider
        />
        <Stat
          label="Last 7 days import"
          value={week?.import_kwh != null ? Number(week.import_kwh).toFixed(1) : "—"}
          unit="kWh"
          accent="error"
          divider
        />
        {latest?.ac_power_kw != null ? (
          <Stat
            label="Latest AC power"
            value={Number(latest.ac_power_kw).toFixed(2)}
            unit="kW"
            divider
          />
        ) : null}
      </div>
    </section>
  );
}

// ── Hero chart ────────────────────────────────────────────────────────────

function HeroChart({ ieSeries, flow, peakKw }) {
  const gridKw = flow?.grid_w != null ? flow.grid_w / 1000 : null;
  const direction =
    gridKw == null ? null :
    gridKw > 0    ? "Exporting" :
    gridKw < 0    ? "Importing" : "Balanced";
  const directionTone =
    direction === "Exporting" ? "text-primary" :
    direction === "Importing" ? "text-error"   :
    "text-on-surface";

  return (
    <section
      className="w-full min-w-0 overflow-hidden rounded-xl border border-outline-variant bg-surface-container-lowest shadow-sm"
      aria-label="Electricity import and export"
    >
      <header className="flex flex-wrap items-start justify-between gap-md border-b border-outline-variant px-md py-md">
        <div className="min-w-0">
          <h2 className="font-[family-name:var(--font-display-serif)] text-headline-md text-on-surface tracking-tight">
            Electricity import / export
          </h2>
          <p className="text-label-sm text-on-surface-variant mt-xs">
            Trailing 12 hours · signed power at the grid meter (kW)
          </p>
        </div>
        <div className="flex flex-wrap items-baseline gap-md">
          <div>
            <span className="text-label-sm font-bold uppercase tracking-wider text-secondary">
              Current grid
            </span>
            <div className="flex items-baseline gap-xs">
              <span className={`font-[family-name:var(--font-display-serif)] text-headline-lg tracking-tight md:text-[2.25rem] ${directionTone}`}>
                {gridKw != null ? Math.abs(gridKw).toFixed(2) : "—"}
              </span>
              {gridKw != null ? (
                <span className="text-headline-md text-on-surface-variant font-semibold">kW</span>
              ) : null}
            </div>
            {direction ? (
              <span className="text-label-sm font-semibold text-on-surface-variant uppercase tracking-wide">
                {direction}
              </span>
            ) : null}
          </div>
          <div className="border-l-2 border-secondary/60 pl-md">
            <span className="text-label-sm uppercase text-on-surface-variant">12 h peak</span>
            <div className="flex items-baseline gap-xs">
              <span className="font-[family-name:var(--font-display-serif)] text-headline-md text-secondary">
                {peakKw != null ? peakKw.toFixed(2) : "—"}
              </span>
              {peakKw != null ? (
                <span className="text-label-sm text-on-surface-variant font-semibold">kW</span>
              ) : null}
            </div>
          </div>
        </div>
      </header>
      <div className="chart-surface relative h-[min(22rem,48vh)] w-full min-h-[240px] rounded-b-lg bg-[linear-gradient(180deg,color-mix(in_srgb,var(--color-primary)_10%,transparent)_0%,transparent_70%)] px-sm pb-sm pt-md">
        <ImportExportChart points={ieSeries} />
      </div>
    </section>
  );
}

// ── Dense 4-tile telemetry strip ──────────────────────────────────────────

function ModularTileStrip({ latest, todaySolarKwh }) {
  return (
    <div className="grid w-full min-w-0 grid-cols-1 items-stretch gap-md sm:grid-cols-2 lg:grid-cols-4">
      <ModularTile
        label="Current solar AC"
        value={latest?.ac_power_kw != null ? Number(latest.ac_power_kw).toFixed(2) : "—"}
        unit="kW"
        icon="electrical_services"
      />
      <ModularTile
        label="Current solar DC"
        value={latest?.dc_power_kw != null ? Number(latest.dc_power_kw).toFixed(2) : "—"}
        unit="kW"
        icon="bolt"
      />
      <ModularTile
        label="Inverter amps"
        value={latest?.ac_amps != null ? Number(latest.ac_amps).toFixed(1) : "—"}
        unit="A"
        icon="settings_input_component"
      />
      <ModularTile
        label="Today's solar"
        value={todaySolarKwh != null ? Number(todaySolarKwh).toFixed(2) : "—"}
        unit="kWh"
        icon="energy_savings_leaf"
      />
    </div>
  );
}

function ModularTile({ label, value, unit, icon }) {
  return (
    <div className="flex h-full min-h-[96px] min-w-0 w-full flex-col justify-between rounded-xl border border-outline-variant bg-surface-container-lowest p-md shadow-sm transition-colors hover:border-secondary">
      <div className="flex items-start justify-between gap-sm">
        <span className="text-label-sm font-bold uppercase tracking-wide text-on-surface-variant">
          {label}
        </span>
        <span
          className="material-symbols-outlined text-secondary opacity-60"
          style={{ fontSize: 20, fontVariationSettings: "'FILL' 1, 'wght' 500, 'GRAD' 0, 'opsz' 24" }}
          aria-hidden
        >
          {icon}
        </span>
      </div>
      <div className="flex items-baseline gap-xs mt-sm">
        <span className="font-[family-name:var(--font-display-serif)] text-headline-lg text-on-surface tracking-tight">
          {value}
        </span>
        <span className="text-label-md text-on-surface-variant font-semibold">{unit}</span>
      </div>
    </div>
  );
}

// ── Lower row: 8/4 split ──────────────────────────────────────────────────

function LowerRow({ solarSeries, ieSeries, latest }) {
  const hasVoltage = (ieSeries || []).some((p) => p?.ac_v != null);

  return (
    <div className="grid w-full min-w-0 grid-cols-1 items-start gap-md lg:grid-cols-12">
      <Card
        title="Solar generation"
        subtitle="Last 7 days · daily energy (kWh)"
        className="min-h-0 min-w-0 lg:col-span-8"
      >
        <div className="h-64 w-full min-h-[200px]">
          <Solar7DayChart points={solarSeries} />
        </div>
      </Card>
      <div className="w-full min-w-0 lg:col-span-4">
        {hasVoltage ? (
          <AcVoltageSpark points={ieSeries} />
        ) : (
          <InverterSnapshotCard latest={latest} />
        )}
      </div>
    </div>
  );
}

function InverterSnapshotCard({ latest }) {
  const rows = [
    { label: "AC voltage", value: latest?.ac_voltage,  unit: "V" },
    { label: "DC voltage", value: latest?.dc_voltage,  unit: "V" },
    { label: "DC amps",    value: latest?.dc_amps,     unit: "A", precision: 1 },
    { label: "AC amps",    value: latest?.ac_amps,     unit: "A", precision: 1 }
  ];
  return (
    <section className="w-full min-w-0 rounded-xl border border-outline-variant bg-surface-container-lowest p-md shadow-sm">
      <div className="mb-sm flex items-center justify-between">
        <h3 className="text-label-sm font-semibold uppercase tracking-wide text-on-surface-variant">
          Inverter snapshot
        </h3>
        {latest?.inverter_status ? (
          <span className="text-label-sm text-primary font-semibold capitalize">
            {String(latest.inverter_status).replace(/_/g, " ")}
          </span>
        ) : null}
      </div>
      <ul className="flex flex-col divide-y divide-outline-variant/60">
        {rows.map((r) => (
          <li key={r.label} className="flex items-baseline justify-between gap-sm py-xs">
            <span className="text-label-sm text-on-surface-variant">{r.label}</span>
            <span className="text-label-md font-semibold text-on-surface tabular-nums">
              {r.value != null ? Number(r.value).toFixed(r.precision || 0) : "—"}
              {r.value != null ? <span className="text-label-sm text-on-surface-variant ml-xs">{r.unit}</span> : null}
            </span>
          </li>
        ))}
      </ul>
    </section>
  );
}

// ── Shared bits ───────────────────────────────────────────────────────────

function Card({ title, subtitle, children, className = "" }) {
  return (
    <section
      className={`w-full min-w-0 rounded-xl border border-outline-variant bg-surface-container-lowest p-md shadow-sm ${className}`.trim()}
    >
      <header className="mb-md border-b border-outline-variant/80 pb-sm">
        <h2 className="font-[family-name:var(--font-display-serif)] text-headline-md text-on-surface tracking-tight">
          {title}
        </h2>
        {subtitle ? (
          <p className="text-label-sm text-on-surface-variant mt-xs">{subtitle}</p>
        ) : null}
      </header>
      {children}
    </section>
  );
}

function Row({ label, value }) {
  return (
    <div className="flex items-baseline justify-between gap-sm py-xs border-b border-outline-variant/40 last:border-b-0">
      <dt className="text-on-surface-variant">{label}</dt>
      <dd className="font-semibold text-on-surface text-right">{value || "—"}</dd>
    </div>
  );
}

function Stat({ label, value, unit, accent, divider }) {
  const accentClass =
    accent === "primary" ? "text-primary" :
    accent === "error"   ? "text-error"   :
    "text-on-surface";
  return (
    <div className={divider ? "pt-md border-t border-outline-variant/40" : ""}>
      <span className="block text-label-sm text-on-surface-variant">{label}</span>
      <div className="flex items-baseline gap-xs">
        <span className={`font-[family-name:var(--font-display-serif)] text-display-sm tracking-tight ${accentClass}`}>
          {value}
        </span>
        <span className="text-label-md text-on-surface-variant font-semibold">{unit}</span>
      </div>
    </div>
  );
}

// ── Helpers ──────────────────────────────────────────────────────────────

function gridDirectionLabel(flow) {
  if (!flow || flow.grid_w == null) return null;
  const kw = flow.grid_w / 1000;
  if (kw > 0)  return `Exporting ${kw.toFixed(2)} kW`;
  if (kw < 0)  return `Importing ${Math.abs(kw).toFixed(2)} kW`;
  return "Balanced";
}

function titleize(value) {
  if (!value) return null;
  return String(value).replace(/_/g, " ").replace(/\b\w/g, (c) => c.toUpperCase());
}

function formatRelative(iso) {
  if (!iso) return null;
  const t = new Date(iso).getTime();
  if (Number.isNaN(t)) return null;
  const seconds = Math.max(0, Math.round((Date.now() - t) / 1000));
  if (seconds < 60)        return `${seconds}s ago`;
  if (seconds < 3600)      return `${Math.round(seconds / 60)}m ago`;
  if (seconds < 86400)     return `${Math.round(seconds / 3600)}h ago`;
  return `${Math.round(seconds / 86400)}d ago`;
}

function peakAbsKw(points) {
  if (!points || points.length === 0) return null;
  let peak = 0;
  for (const p of points) {
    const kw = Number(p?.kw);
    if (!Number.isNaN(kw) && Math.abs(kw) > peak) peak = Math.abs(kw);
  }
  return peak;
}

function round1(n) {
  if (n == null || Number.isNaN(Number(n))) return null;
  return Math.round(Number(n) * 10) / 10;
}

function inverterTempTone(tempC) {
  if (tempC == null || Number.isNaN(Number(tempC))) return "neutral";
  if (tempC >= 65) return "error";
  if (tempC >= 55) return "warn";
  return "primary";
}
