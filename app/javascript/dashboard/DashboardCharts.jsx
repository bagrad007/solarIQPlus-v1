// Site dashboard React island: range-aware solar chart, DC/AC gauges, inverter
// snapshot, today's yield, AC voltage spark (when telemetry carries ac_voltage),
// and ambient / forecast context. Data is server-rolled-up only.

import { useMemo, useState, useEffect } from "react";
import SolarGenerationChart from "./SolarGenerationChart.jsx";
import GenerationGauge from "./GenerationGauge.jsx";
import AcVoltageSpark from "./AcVoltageSpark.jsx";

export default function DashboardCharts({ payload }) {
  const chart = payload?.chart || {};
  const gauges = payload?.gauges || {};
  const latest = payload?.latest || {};
  const totals = payload?.totals || {};
  const today = payload?.today || {};
  const seriesByRange = chart.solar_series_by_range || {};

  const availableRanges = useMemo(
    () =>
      Object.keys(seriesByRange).filter(
        (k) => Array.isArray(seriesByRange[k]) && seriesByRange[k].length >= 2
      ),
    [seriesByRange]
  );

  const preferredDefault =
    chart.default_chart_range ||
    (availableRanges.includes("1d") ? "1d" : availableRanges[0]) ||
    "1d";

  const [chartRange, setChartRange] = useState(preferredDefault);

  useEffect(() => {
    if (availableRanges.includes(chartRange)) return;
    const next =
      (chart.default_chart_range && availableRanges.includes(chart.default_chart_range)
        ? chart.default_chart_range
        : null) ||
      (availableRanges.includes("1d") ? "1d" : null) ||
      availableRanges[0];
    if (next) setChartRange(next);
  }, [availableRanges, chartRange, chart.default_chart_range]);

  const voltagePoints = seriesByRange[chartRange] || chart.solar_today_series || [];

  const acKw = Number(latest?.ac_power_kw);
  const dcKw = Number(latest?.dc_power_kw);
  const acEff =
    acKw > 0 && dcKw > 0 ? ((acKw / dcKw) * 100).toFixed(1) : null;

  return (
    <div
      className="dashboard-reveal flex w-full min-w-0 flex-col gap-lg"
      data-dashboard-section="root"
    >
      <section
        className="w-full min-w-0 overflow-hidden rounded-xl border border-outline-variant bg-surface-container-lowest shadow-sm"
        aria-label="Solar generation"
      >
        <header className="flex flex-wrap items-start justify-between gap-sm border-b border-outline-variant px-md py-md">
          <div>
            <h2 className="font-[family-name:var(--font-display-serif)] text-headline-md text-on-surface tracking-tight">
              Solar generation
            </h2>
            <p className="text-label-sm text-on-surface-variant mt-xs">
              Real-time performance across sampled telemetry
            </p>
          </div>
          <div className="flex items-baseline gap-md">
            <div>
              <span className="text-label-sm font-bold uppercase tracking-wider text-secondary">
                Current power
              </span>
              <div className="flex items-baseline gap-xs">
                <span className="font-[family-name:var(--font-display-serif)] text-headline-lg text-primary tracking-tight md:text-[2.25rem]">
                  {latest.ac_power_kw != null ? Number(latest.ac_power_kw).toFixed(1) : "—"}
                </span>
                {latest.ac_power_kw != null ? (
                  <span className="text-headline-md text-on-surface-variant font-semibold">kW</span>
                ) : null}
              </div>
            </div>
          </div>
        </header>
        <div className="w-full min-w-0 px-md py-md">
          <SolarGenerationChart
            seriesByRange={seriesByRange}
            selectedRange={chartRange}
            onSelectRange={setChartRange}
          />
        </div>
      </section>

      <div className="grid w-full min-w-0 grid-cols-1 items-stretch gap-md sm:grid-cols-2 lg:grid-cols-4">
        <GenerationGauge label="Current solar DC" gauge={gauges.dc} accent="solar" />
        <GenerationGauge label="Current solar AC" gauge={gauges.ac} accent="primary" />
        <InverterAmpsTile latest={latest} />
        <TodayYieldTile kwh={totals.today_kwh} acEff={acEff} />
      </div>

      <div className="w-full min-w-0">
        <section
          className="w-full min-w-0 overflow-hidden rounded-xl border border-outline-variant bg-surface-container-lowest"
          aria-label="Inverter electrical snapshot"
        >
          <header className="border-b border-outline-variant px-md py-md">
            <h3 className="font-[family-name:var(--font-display-serif)] text-headline-md text-on-surface tracking-tight">
              Inverter telemetry
            </h3>
          </header>
          <div className="grid w-full min-w-0 grid-cols-2 divide-x divide-y divide-outline-variant sm:grid-cols-4 sm:divide-y-0">
            <TelemetryCell label="DC amps" value={latest.dc_amps} unit="A" />
            <TelemetryCell label="AC amps" value={latest.ac_amps} unit="A" />
            <TelemetryCell label="DC voltage" value={latest.dc_voltage} unit="V" />
            <TelemetryCell label="AC voltage" value={latest.ac_voltage} unit="V" />
          </div>
          <footer className="flex flex-wrap items-center justify-between gap-sm border-t border-outline-variant bg-surface-container-low px-md py-sm">
            <span className="text-label-sm text-on-surface-variant italic">
              Latest sample
              {today.latest_at ? ` · ${formatShortIso(today.latest_at)}` : ""}
            </span>
            {latest.inverter_status ? (
              <span className="text-label-sm font-semibold text-primary capitalize">
                {String(latest.inverter_status).replace(/_/g, " ")}
              </span>
            ) : null}
          </footer>
        </section>
      </div>

      <div className="w-full min-w-0">
        <AcVoltageSpark points={voltagePoints} />
      </div>
    </div>
  );
}

function TelemetryCell({ label, value, unit }) {
  const v = value != null && !Number.isNaN(Number(value)) ? Number(value).toFixed(1) : "—";
  return (
    <div className="min-w-0 p-lg text-center">
      <p className="text-label-sm text-on-surface-variant mb-md uppercase tracking-wide">{label}</p>
      <span className="font-[family-name:var(--font-display-serif)] text-headline-lg text-on-surface tracking-tight">
        {v}
      </span>
      <span className="block text-label-sm text-on-surface-variant mt-xs">{unit}</span>
    </div>
  );
}

function InverterAmpsTile({ latest }) {
  const dc = latest?.dc_amps;
  const ac = latest?.ac_amps;
  const show = dc != null || ac != null;
  const line =
    dc != null && ac != null
      ? `DC ${Number(dc).toFixed(1)} A · AC ${Number(ac).toFixed(1)} A`
      : dc != null
        ? `DC ${Number(dc).toFixed(1)} A`
        : ac != null
          ? `AC ${Number(ac).toFixed(1)} A`
          : null;

  return (
    <div className="flex h-full min-h-0 min-w-0 w-full flex-col justify-start rounded-xl border border-outline-variant bg-surface-container-lowest px-md py-sm motion-safe:animate-[dashboard-reveal_0.5s_ease-out_both]">
      <div className="mb-xs flex min-h-[1.5rem] items-center gap-sm">
        <span
          className="material-symbols-outlined shrink-0 text-[20px] leading-none text-secondary/75"
          style={{ fontVariationSettings: "'FILL' 1, 'wght' 500, 'GRAD' 0, 'opsz' 24" }}
          aria-hidden
        >
          electrical_services
        </span>
        <span className="min-w-0 flex-1 text-label-sm font-semibold uppercase leading-snug tracking-wide text-on-surface-variant">
          Inverter current
        </span>
      </div>
      {show ? (
        <>
          <p className="font-[family-name:var(--font-display-serif)] text-headline-lg text-on-surface tracking-tight">
            {line}
          </p>
          <p className="mt-xs text-label-sm text-on-surface-variant">Latest sample</p>
        </>
      ) : (
        <p className="text-label-md text-on-surface-variant">—</p>
      )}
    </div>
  );
}

function TodayYieldTile({ kwh, acEff }) {
  const v = kwh != null && !Number.isNaN(Number(kwh)) ? Number(kwh).toFixed(2) : "—";
  return (
    <div className="flex h-full min-h-0 min-w-0 w-full flex-col justify-start rounded-xl border border-outline-variant bg-surface-container-lowest px-md py-sm motion-safe:animate-[dashboard-reveal_0.5s_ease-out_both]">
      <div className="mb-xs flex min-h-[1.5rem] items-center gap-sm">
        <span
          className="material-symbols-outlined shrink-0 text-[20px] leading-none text-solar-accent/85"
          style={{ fontVariationSettings: "'FILL' 1, 'wght' 500, 'GRAD' 0, 'opsz' 24" }}
          aria-hidden
        >
          energy_savings_leaf
        </span>
        <span className="min-w-0 flex-1 text-label-sm font-semibold uppercase leading-snug tracking-wide text-on-surface-variant">
          {`Today's yield`}
        </span>
      </div>
      <div className="flex items-baseline gap-xs flex-wrap">
        <span className="font-[family-name:var(--font-display-serif)] text-headline-lg text-on-surface tracking-tight">
          {v}
        </span>
        <span className="text-label-md text-on-surface-variant font-medium">kWh</span>
      </div>
      {acEff ? (
        <p className="mt-xs text-label-sm font-semibold text-primary">{acEff}% DC→AC</p>
      ) : (
        <p className="mt-xs text-label-sm text-on-surface-variant">Integrated today</p>
      )}
    </div>
  );
}

function formatShortIso(iso) {
  const d = new Date(iso);
  if (Number.isNaN(d.getTime())) return "";
  return d.toLocaleString(undefined, { month: "short", day: "numeric", hour: "2-digit", minute: "2-digit" });
}
