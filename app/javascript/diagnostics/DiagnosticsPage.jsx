// Diagnostics console — layout aligned with the Stitch “hero + bento + footer”
// mock: full-width lead chart, narrow column of summary tiles + wide solar strip,
// then today pie + topology, then today metric tiles. Data from SiteDiagnostics.

import StatTile from "./StatTile.jsx";
import ImportExportChart from "./ImportExportChart.jsx";
import ImportExportPie from "./ImportExportPie.jsx";
import EnergyFlowPanel from "./EnergyFlowPanel.jsx";
import Solar7DayChart from "./Solar7DayChart.jsx";
import { fahrenheitFromCelsius } from "../lib/temperature.js";

export default function DiagnosticsPage({ payload }) {
  const today = payload.today || {};
  const todayPie = payload.today_pie || {};
  const energyFlow = payload.energy_flow || {};
  const week = payload.last_7_days || {};
  const ieSeries = payload.import_export_series || [];
  const solarSeries = payload.solar_7d_series || [];

  return (
    <div className="dashboard-reveal flex w-full min-w-0 max-w-full flex-col gap-lg">
      {/* Hero — full-width lead chart (mock: solar generation today band) */}
      <Card
        title="Electricity import / export"
        subtitle="Trailing 12 hours · signed power at the grid meter (kW)"
        className="overflow-hidden"
      >
        <div className="chart-surface relative h-[min(22rem,48vh)] w-full min-h-[220px] rounded-lg bg-[linear-gradient(180deg,color-mix(in_srgb,var(--color-primary)_10%,transparent)_0%,transparent_70%)]">
          <ImportExportChart points={ieSeries} />
        </div>
      </Card>

      {/* Bento — mock: stacked left rail + wide telemetry panel */}
      <div className="grid w-full min-w-0 grid-cols-1 items-start gap-lg lg:grid-cols-12">
        <div className="flex w-full min-w-0 flex-col gap-md self-start lg:col-span-4">
          <StatTile
            label="Last 7 days export"
            value={week.export_kwh}
            unit="kWh"
            tone="neutral"
            large
          />
          <StatTile
            label="Last 7 days import"
            value={week.import_kwh}
            unit="kWh"
            tone="neutral"
            large
          />
        </div>
        <Card
          title="Solar generation"
          subtitle="Last 7 days · daily energy (kWh)"
          className="min-h-0 min-w-0 lg:col-span-8"
        >
          <div className="h-64 w-full min-h-[200px]">
            <Solar7DayChart points={solarSeries} />
          </div>
        </Card>
      </div>

      {/* Two-up — mock: forecast-style split; here today pie + topology */}
      <div className="grid w-full min-w-0 grid-cols-1 items-stretch gap-lg lg:grid-cols-2">
        <Card title="Import / export today" subtitle="Self-use vs grid (integrated kWh)" className="min-w-0">
          <ImportExportPie pie={todayPie} />
        </Card>
        <Card title="Live energy topology" subtitle="Directed flows from the latest snapshot" className="min-w-0">
          <EnergyFlowPanel flow={energyFlow} />
        </Card>
      </div>

      {/* Today metrics — mock-style dense strip */}
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

function inverterTempTone(tempC) {
  if (tempC == null || Number.isNaN(Number(tempC))) return "neutral";
  if (tempC >= 65) return "error";
  if (tempC >= 55) return "warn";
  return "primary";
}
