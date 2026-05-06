// Diagnostics console — full-width status + asset summary row on top, then the
// hero import/export chart and dense telemetry (tiles + full-width 7-day solar),
// then full-width topology, then today's energy mix beside stacked forecast
// tiles. The topology diagram uses the full content width so the diagram +
// metrics column are not cramped.
//
// All values come from `SiteDiagnostics`. We never invent data:
//   * "No active alarms" copy renders only when the latest reading is `normal`;
//     "Awaiting telemetry" renders when the site has produced no rows yet.
import ImportExportChart from "./ImportExportChart.jsx";
import TodayEnergyMix from "./TodayEnergyMix.jsx";
import ForecastTile from "./ForecastTile.jsx";
import EnergyFlowPanel from "./EnergyFlowPanel.jsx";
import Solar7DayChart from "./Solar7DayChart.jsx";
import { fahrenheitFromCelsius } from "../lib/temperature.js";

const STATUS_TONE = {
  normal:   { surface: "bg-green-50  border-green-500/30  text-green-700",  caption: "text-green-700",  dot: "bg-green-500",         label: "Normal",       sub: "No active alarms" },
  warn:     { surface: "bg-amber-50  border-amber-500/40  text-amber-700",  caption: "text-amber-700",  dot: "bg-amber-500",         label: "Warning",      sub: "Investigate this site" },
  critical: { surface: "bg-red-50    border-red-500/40    text-red-700",    caption: "text-red-700",    dot: "bg-red-500",           label: "Critical",     sub: "Action required" },
  unknown:  { surface: "bg-surface-container-high border-outline-variant text-on-surface-variant", caption: "text-on-surface-variant", dot: "bg-on-surface-variant", label: "No telemetry", sub: "Awaiting first reading" }
};

export default function DiagnosticsPage({ payload }) {
  const today = payload.today || {};
  const todayPie = payload.today_pie || {};
  const energyFlow = payload.energy_flow || {};
  const latest = payload.latest || {};
  const week = payload.last_7_days || {};
  const ieSeries = payload.import_export_series || [];
  const solarSeries = payload.solar_7d_series || [];
  const forecast = payload.forecast || {};

  const todaySolarKwh = round1((todayPie.exported_kwh || 0) + (todayPie.self_consumption_kwh || 0));
  const peakKw = peakAbsKw(ieSeries);
  const inverterTempF = today.inverter_temp_f ?? fahrenheitFromCelsius(today.inverter_temp_c);

  return (
    <div className="dashboard-reveal flex w-full min-w-0 max-w-full flex-col gap-md">
      {/* Status + assets span the content width above the hero chart (stacked on small screens). */}
      <div className="grid w-full min-w-0 grid-cols-1 items-stretch gap-md lg:grid-cols-2">
        <SystemStatusCard latest={latest} flow={energyFlow} inverterTempF={inverterTempF} />
        <AssetSummaryCard
          week={week}
          todaySolarKwh={todaySolarKwh}
          today={today}
        />
      </div>

      <div className="flex w-full min-w-0 flex-col gap-md">
        <HeroChart ieSeries={ieSeries} flow={energyFlow} peakKw={peakKw} />
        <ModularTileStrip latest={latest} todaySolarKwh={todaySolarKwh} />
        <LowerRow solarSeries={solarSeries} />
      </div>

      {/* Topology gets the full content width so the 480 px diagram + metrics
          column can breathe instead of fighting a 4-col card. */}
      <Card
        title="Live energy topology"
        subtitle="Directed flows from the latest telemetry snapshot"
      >
        <EnergyFlowPanel flow={energyFlow} />
      </Card>

      {/* Today's mix (wide) + stacked forecast tiles — matches operational forecast data. */}
      <div className="grid w-full min-w-0 grid-cols-1 items-stretch gap-md lg:grid-cols-3">
        <Card
          title="Today's energy mix"
          subtitle="Self-use vs grid export (integrated kWh)"
          className="min-w-0 lg:col-span-2"
        >
          <TodayEnergyMix pie={todayPie} />
        </Card>
        <div className="flex min-w-0 flex-col gap-md lg:col-span-1" aria-label="Forecast solar production">
          <ForecastTile
            label="Forecast Solar Production Today"
            projectedKwh={forecast.today_kwh}
            condition={forecast.today_condition}
            highF={forecast.today_temp_high_f}
          />
          <ForecastTile
            label="Forecast Solar Production Tomorrow"
            projectedKwh={forecast.tomorrow_kwh}
            condition={forecast.tomorrow_condition}
            highF={forecast.tomorrow_temp_high_f}
          />
        </div>
      </div>
    </div>
  );
}

// ── Top row: status + asset summary ───────────────────────────────────────

function SystemStatusCard({ latest, flow, inverterTempF }) {
  const state = latest?.alarm_state ?? (latest?.recorded_at ? "normal" : "unknown");
  const tone = STATUS_TONE[state] || STATUS_TONE.unknown;

  return (
    <section
      className="w-full min-w-0 rounded-xl border border-outline-variant bg-surface-container-lowest p-md shadow-sm"
      aria-label="System status"
    >
      <div className="flex items-center justify-between mb-md">
        <span className="text-label-sm font-bold uppercase tracking-wide text-on-surface-variant">
          System status
        </span>
        <span className={`inline-flex h-2.5 w-2.5 rounded-full ${tone.dot}`} aria-hidden />
      </div>

      <div className={`text-center rounded-xl border-2 px-md py-lg ${tone.surface}`}>
        <span className="block font-[family-name:var(--font-display-serif)] text-display-md tracking-tight">
          {tone.label}
        </span>
        <span className={`block text-label-sm uppercase tracking-widest mt-xs ${tone.caption}`}>
          {tone.sub}
        </span>
      </div>

      <dl className="mt-md flex flex-col text-label-sm">
        <Row label="Grid direction"   value={gridDirectionLabel(flow)} />
        <Row label="Inverter status"  value={titleize(latest?.inverter_status)} />
        <Row label="Inverter temp"    value={inverterTempF != null ? `${Number(inverterTempF).toFixed(1)} °F` : null} />
        <Row label="Latest sample"    value={formatRelative(latest?.recorded_at)} />
      </dl>
    </section>
  );
}

function AssetSummaryCard({ week, todaySolarKwh, today }) {
  return (
    <section
      className="w-full min-w-0 rounded-xl border border-outline-variant bg-surface-container-lowest p-md shadow-sm"
      aria-label="Asset summary"
    >
      <span className="text-label-sm font-bold uppercase tracking-wide text-on-surface-variant block mb-md">
        Asset summary
      </span>

      <div className="flex flex-col gap-lg">
        <Stat
          label="Solar generated today"
          value={compactNumber(todaySolarKwh)}
          unit="kWh"
          accent="solar"
        />
        <Stat
          label="Self-consumption today"
          value={compactNumber(today?.self_consumption_kwh)}
          unit="kWh"
          accent="primary"
          divider
        />
        <Stat
          label="Last 7 days export"
          value={compactNumber(week?.export_kwh)}
          unit="kWh"
          divider
        />
        <Stat
          label="Last 7 days import"
          value={compactNumber(week?.import_kwh)}
          unit="kWh"
          accent="error"
          divider
        />
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
        value={compactNumber(latest?.ac_power_kw)}
        unit="kW"
        icon="electrical_services"
      />
      <ModularTile
        label="Current solar DC"
        value={compactNumber(latest?.dc_power_kw)}
        unit="kW"
        icon="bolt"
      />
      <ModularTile
        label="Inverter amps"
        value={compactNumber(latest?.ac_amps, { sub100Precision: 1 })}
        unit="A"
        icon="settings_input_component"
      />
      <ModularTile
        label="Today's solar"
        value={compactNumber(todaySolarKwh)}
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
        <span className="min-w-0 flex-1 text-label-sm font-bold uppercase tracking-wide text-on-surface-variant break-words">
          {label}
        </span>
        <span
          className="material-symbols-outlined shrink-0 text-secondary opacity-60"
          style={{ fontSize: 20, fontVariationSettings: "'FILL' 1, 'wght' 500, 'GRAD' 0, 'opsz' 24" }}
          aria-hidden
        >
          {icon}
        </span>
      </div>
      {/* flex-wrap lets the unit drop to a new line on narrow tiles when the
          numeric value is wide (e.g. "3,547 kWh" on a ~150 px tile). */}
      <div className="mt-sm flex flex-wrap items-baseline gap-x-xs gap-y-0">
        <span className="font-[family-name:var(--font-display-serif)] text-headline-lg text-on-surface tracking-tight tabular-nums">
          {value}
        </span>
        <span className="text-label-md text-on-surface-variant font-semibold">{unit}</span>
      </div>
    </div>
  );
}

// ── 7-day solar (full width; inverter detail lives in telemetry + topology) ─

function LowerRow({ solarSeries }) {
  return (
    <Card title="Solar generation" subtitle="Last 7 days · daily energy (kWh)" className="min-h-0 min-w-0">
      <div className="h-[min(22rem,50vh)] w-full min-h-[240px]">
        <Solar7DayChart points={solarSeries} />
      </div>
    </Card>
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
    accent === "primary" ? "text-primary"      :
    accent === "error"   ? "text-error"        :
    accent === "solar"   ? "text-secondary"    :
    "text-on-surface";
  return (
    <div className={divider ? "pt-md border-t border-outline-variant/40" : ""}>
      <span className="block text-label-sm text-on-surface-variant">{label}</span>
      <div className="flex flex-wrap items-baseline gap-x-xs gap-y-0">
        <span className={`font-[family-name:var(--font-display-serif)] text-display-sm tracking-tight tabular-nums ${accentClass}`}>
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

// Format a numeric value at a density that fits the diagnostics tiles even
// at narrower lg widths (~150 px columns). Drops decimal noise as the value
// grows, then folds 7-digit watt-hour totals into "M" notation so we never
// print "12,345,678 kWh" inside a 16 px-padded tile.
function compactNumber(value, { sub100Precision = 2 } = {}) {
  if (value == null) return "—";
  const n = Number(value);
  if (Number.isNaN(n)) return "—";
  const abs = Math.abs(n);
  if (abs >= 1_000_000)  return `${(n / 1_000_000).toFixed(abs >= 10_000_000 ? 0 : 1)}M`;
  if (abs >= 1000)       return n.toLocaleString(undefined, { maximumFractionDigits: 0 });
  if (abs >= 100)        return n.toFixed(1);
  return n.toFixed(sub100Precision);
}
