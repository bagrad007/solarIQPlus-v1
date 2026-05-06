// Solar kW time-series with LIVE / 1D / 1W / 1M toggles. Controlled by parent
// so the same window can drive companion series (e.g. AC voltage sparkline).

import { useMemo } from "react";
import {
  ResponsiveContainer,
  AreaChart,
  Area,
  XAxis,
  YAxis,
  CartesianGrid,
  Tooltip
} from "recharts";

const SOLAR_COLOR = "var(--color-secondary)";
const AXIS_COLOR  = "var(--color-on-surface-variant)";
const GRID_COLOR  = "var(--color-outline-variant)";

const RANGE_LABELS = {
  live: "Live",
  "1d": "1D",
  "1w": "1W",
  "1m": "1M"
};

export default function SolarGenerationChart({
  seriesByRange = {},
  selectedRange = "1d",
  onSelectRange
}) {
  const available = useMemo(() => {
    return Object.keys(seriesByRange).filter(
      (k) => Array.isArray(seriesByRange[k]) && seriesByRange[k].length >= 2
    );
  }, [seriesByRange]);

  const range = available.includes(selectedRange) ? selectedRange : available[0] || "1d";
  const series = seriesByRange[range] || [];
  const data = useMemo(
    () =>
      series.map((p) => ({
        t: p.t,
        label: formatTick(p.t, range),
        kw: Math.max(0, Number(p.kw) || 0)
      })),
    [series, range]
  );

  const peakKw = useMemo(
    () => data.reduce((m, d) => Math.max(m, d.kw), 0),
    [data]
  );

  if (data.length === 0) {
    return <Empty>No telemetry for the selected window yet.</Empty>;
  }

  return (
    <div className="flex w-full min-w-0 flex-col gap-md">
      <div className="flex flex-wrap items-start justify-between gap-md">
        <div className="flex flex-wrap gap-xs">
          {available.map((key) => (
            <button
              key={key}
              type="button"
              onClick={() => onSelectRange?.(key)}
              className={
                range === key
                  ? "rounded-md bg-surface-container-high px-sm py-1 text-[10px] font-bold uppercase tracking-wide text-on-surface ring-1 ring-inset ring-outline-variant hover:opacity-95"
                  : "rounded-md px-sm py-1 text-[10px] font-bold uppercase tracking-wide text-on-surface-variant transition-colors hover:bg-surface-container-low"
              }
            >
              {RANGE_LABELS[key] || key}
            </button>
          ))}
        </div>
        <div className="hidden sm:flex items-baseline gap-lg text-end">
          <div>
            <span className="block text-[10px] font-bold uppercase tracking-wider text-secondary">
              Peak in view
            </span>
            <span className="font-[family-name:var(--font-display-serif)] text-headline-md text-on-surface">
              {peakKw.toFixed(1)}
              <span className="text-label-md text-on-surface-variant ms-xs">kW</span>
            </span>
          </div>
        </div>
      </div>

      <div className="relative w-full h-[min(22rem,55vw)] min-h-[220px] rounded-lg bg-[linear-gradient(180deg,color-mix(in_srgb,var(--color-secondary)_12%,transparent)_0%,transparent_72%)]">
        <ResponsiveContainer width="100%" height="100%">
          <AreaChart data={data} margin={{ top: 12, right: 8, bottom: 4, left: 0 }}>
            <defs>
              <linearGradient id="dashboard-solar-range" x1="0" y1="0" x2="0" y2="1">
                <stop offset="0%" stopColor={SOLAR_COLOR} stopOpacity={0.55} />
                <stop offset="100%" stopColor={SOLAR_COLOR} stopOpacity={0.06} />
              </linearGradient>
            </defs>
            <CartesianGrid stroke={GRID_COLOR} strokeDasharray="2 3" vertical={false} />
            <XAxis
              dataKey="label"
              stroke={AXIS_COLOR}
              tick={{ fill: AXIS_COLOR, fontSize: 10 }}
              minTickGap={24}
            />
            <YAxis
              stroke={AXIS_COLOR}
              tick={{ fill: AXIS_COLOR, fontSize: 10 }}
              tickFormatter={(v) => `${v} kW`}
              width={52}
            />
            <Tooltip
              contentStyle={{
                background: "var(--color-surface-container-high)",
                border: `1px solid ${GRID_COLOR}`,
                color: "var(--color-on-surface)",
                fontSize: 12
              }}
              formatter={(v) => [`${Number(v).toFixed(2)} kW`, "Solar"]}
            />
            <Area
              type="monotone"
              dataKey="kw"
              stroke={SOLAR_COLOR}
              strokeWidth={2}
              fill="url(#dashboard-solar-range)"
              isAnimationActive={false}
            />
          </AreaChart>
        </ResponsiveContainer>
      </div>
    </div>
  );
}

function formatTick(iso, rangeKey) {
  const d = new Date(iso);
  if (Number.isNaN(d.getTime())) return "";
  if (rangeKey === "1w" || rangeKey === "1m") {
    return `${d.getMonth() + 1}/${d.getDate()}`;
  }
  return `${d.getHours().toString().padStart(2, "0")}:${d.getMinutes().toString().padStart(2, "0")}`;
}

function Empty({ children }) {
  return (
    <div className="text-label-md text-on-surface-variant italic py-md">{children}</div>
  );
}
