// Sparkline of AC mains voltage when points carry +ac_v+ from telemetry.

import {
  ResponsiveContainer,
  LineChart,
  Line,
  XAxis,
  YAxis,
  Tooltip,
  CartesianGrid
} from "recharts";

const STROKE = "var(--color-secondary)";
const AXIS = "var(--color-on-surface-variant)";
const GRID = "var(--color-outline-variant)";

export default function AcVoltageSpark({ points }) {
  const data = (points || [])
    .filter((p) => p.ac_v != null && !Number.isNaN(Number(p.ac_v)))
    .map((p) => ({
      label: formatTick(p.t),
      v: Number(p.ac_v)
    }));

  if (data.length < 2) {
    return null;
  }

  return (
    <div className="w-full min-w-0 rounded-xl border border-outline-variant bg-surface-container-lowest p-md">
      <div className="flex items-center justify-between gap-sm mb-sm">
        <h3 className="text-label-sm font-semibold uppercase tracking-wide text-on-surface-variant">
          AC mains voltage (sampled)
        </h3>
      </div>
      <div className="h-28 w-full">
        <ResponsiveContainer width="100%" height="100%">
          <LineChart data={data} margin={{ top: 4, right: 4, left: 0, bottom: 0 }}>
            <CartesianGrid stroke={GRID} strokeDasharray="2 3" vertical={false} />
            <XAxis dataKey="label" tick={{ fill: AXIS, fontSize: 9 }} stroke={AXIS} />
            <YAxis
              domain={["dataMin - 5", "dataMax + 5"]}
              tick={{ fill: AXIS, fontSize: 9 }}
              stroke={AXIS}
              width={40}
              tickFormatter={(v) => `${Math.round(v)}`}
            />
            <Tooltip
              formatter={(v) => [`${Number(v).toFixed(1)} V`, "AC"]}
              contentStyle={{
                background: "var(--color-surface-container-high)",
                border: `1px solid ${GRID}`,
                fontSize: 11
              }}
            />
            <Line type="monotone" dataKey="v" stroke={STROKE} strokeWidth={2} dot={false} isAnimationActive={false} />
          </LineChart>
        </ResponsiveContainer>
      </div>
    </div>
  );
}

function formatTick(iso) {
  const d = new Date(iso);
  if (Number.isNaN(d.getTime())) return "";
  return `${d.getHours().toString().padStart(2, "0")}:${d.getMinutes().toString().padStart(2, "0")}`;
}
