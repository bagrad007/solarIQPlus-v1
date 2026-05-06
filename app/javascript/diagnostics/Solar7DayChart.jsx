// Daily kWh bars for the trailing 7 days. The presenter always returns
// exactly 7 buckets (even if some are zero), so the chart never has to
// invent missing days client-side.

import {
  ResponsiveContainer,
  BarChart,
  Bar,
  XAxis,
  YAxis,
  CartesianGrid,
  Tooltip
} from "recharts";

const BAR_COLOR  = "var(--color-primary)";
const AXIS_COLOR = "var(--color-on-surface-variant)";
const GRID_COLOR = "var(--color-outline-variant)";

const DAY_LABELS = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];

export default function Solar7DayChart({ points }) {
  if (!points || points.length === 0) {
    return (
      <div className="text-label-md text-on-surface-variant italic py-md">
        No telemetry in the last 7 days.
      </div>
    );
  }

  const data = points.map((p) => ({
    d: p.d,
    label: dayLabel(p.d),
    kwh: p.kwh
  }));

  return (
    <div className="h-full w-full min-h-[200px]">
      <ResponsiveContainer width="100%" height="100%">
        <BarChart data={data} margin={{ top: 16, right: 12, bottom: 0, left: 0 }}>
          <CartesianGrid stroke={GRID_COLOR} strokeDasharray="2 3" vertical={false} />
          <XAxis
            dataKey="label"
            stroke={AXIS_COLOR}
            tick={{ fill: AXIS_COLOR, fontSize: 11 }}
          />
          <YAxis
            stroke={AXIS_COLOR}
            tick={{ fill: AXIS_COLOR, fontSize: 11 }}
            tickFormatter={(v) => `${v}`}
            width={48}
            label={{
              value: "kWh",
              angle: -90,
              position: "insideLeft",
              fill: AXIS_COLOR,
              fontSize: 11,
              offset: 12
            }}
          />
          <Tooltip
            contentStyle={{
              background: "var(--color-surface-container-high)",
              border: `1px solid ${GRID_COLOR}`,
              color: "var(--color-on-surface)",
              fontSize: 12
            }}
            formatter={(v) => [`${Number(v).toFixed(1)} kWh`, "Generation"]}
            labelFormatter={(label, payload) => {
              const row = payload && payload[0] && payload[0].payload;
              return row ? row.d : label;
            }}
          />
          <Bar dataKey="kwh" fill={BAR_COLOR} radius={[3, 3, 0, 0]} isAnimationActive={false} />
        </BarChart>
      </ResponsiveContainer>
    </div>
  );
}

function dayLabel(iso) {
  const d = new Date(`${iso}T12:00:00Z`);
  return DAY_LABELS[d.getUTCDay()];
}
