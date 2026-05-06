// Signed import/export area chart. Positive values (export) fill above the
// zero line; negative values (import) fill below. The fill color flips so the
// reader doesn't have to inspect the axis to tell direction.
//
// Recharts doesn't ship a "split fill at threshold" primitive, so we render
// two stacked Area series gated through a single SVG <linearGradient> that
// straddles zero. Anything above the zero crossing renders in the export
// color; anything below renders in the import color.

import {
  ResponsiveContainer,
  AreaChart,
  Area,
  XAxis,
  YAxis,
  CartesianGrid,
  Tooltip,
  ReferenceLine
} from "recharts";

const EXPORT_COLOR = "var(--color-primary)";
const IMPORT_COLOR = "var(--color-error)";
const AXIS_COLOR   = "var(--color-on-surface-variant)";
const GRID_COLOR   = "var(--color-outline-variant)";

export default function ImportExportChart({ points }) {
  if (!points || points.length === 0) {
    return <Empty>No telemetry in the last 12 hours.</Empty>;
  }

  const data = points.map((p) => ({
    t: p.t,
    label: formatTime(p.t),
    kw: p.kw
  }));

  const min = Math.min(0, ...data.map((d) => d.kw));
  const max = Math.max(0, ...data.map((d) => d.kw));
  const span = max - min || 1;
  const zeroOffset = max / span;

  return (
    <div className="h-full w-full min-h-[200px]">
      <ResponsiveContainer width="100%" height="100%">
        <AreaChart data={data} margin={{ top: 16, right: 12, bottom: 0, left: 0 }}>
          <defs>
            <linearGradient id="diag-import-export" x1="0" y1="0" x2="0" y2="1">
              <stop offset="0%"                       stopColor={EXPORT_COLOR} stopOpacity={0.55} />
              <stop offset={`${zeroOffset * 100}%`}    stopColor={EXPORT_COLOR} stopOpacity={0.05} />
              <stop offset={`${zeroOffset * 100}%`}    stopColor={IMPORT_COLOR} stopOpacity={0.05} />
              <stop offset="100%"                      stopColor={IMPORT_COLOR} stopOpacity={0.55} />
            </linearGradient>
          </defs>
          <CartesianGrid stroke={GRID_COLOR} strokeDasharray="2 3" vertical={false} />
          <XAxis
            dataKey="label"
            stroke={AXIS_COLOR}
            tick={{ fill: AXIS_COLOR, fontSize: 11 }}
            minTickGap={32}
          />
          <YAxis
            stroke={AXIS_COLOR}
            tick={{ fill: AXIS_COLOR, fontSize: 11 }}
            tickFormatter={(v) => `${v} kW`}
            width={56}
          />
          <Tooltip
            contentStyle={{
              background: "var(--color-surface-container-high)",
              border: `1px solid ${GRID_COLOR}`,
              color: "var(--color-on-surface)",
              fontSize: 12
            }}
            formatter={(v) => [`${Number(v).toFixed(2)} kW`, v >= 0 ? "Export" : "Import"]}
          />
          <ReferenceLine y={0} stroke={AXIS_COLOR} strokeWidth={1} />
          <Area
            type="monotone"
            dataKey="kw"
            stroke={EXPORT_COLOR}
            strokeWidth={1.5}
            fill="url(#diag-import-export)"
            isAnimationActive={false}
          />
        </AreaChart>
      </ResponsiveContainer>
    </div>
  );
}

function formatTime(iso) {
  const d = new Date(iso);
  return `${d.getHours().toString().padStart(2, "0")}:${d.getMinutes().toString().padStart(2, "0")}`;
}

function Empty({ children }) {
  return (
    <div className="text-label-md text-on-surface-variant italic py-md">{children}</div>
  );
}
