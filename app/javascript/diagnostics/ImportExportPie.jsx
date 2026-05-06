// Two-slice pie: today's exported energy vs today's self-consumed energy.
// Both values come from the SiteDiagnostics presenter's `today_pie` slice and
// are already in kWh.

import {
  ResponsiveContainer,
  PieChart,
  Pie,
  Cell,
  Tooltip,
  Legend
} from "recharts";

const EXPORT_COLOR = "var(--color-primary)";
const SELF_COLOR   = "var(--color-tertiary)";
const GRID_COLOR   = "var(--color-outline-variant)";
const TEXT_COLOR   = "var(--color-on-surface)";

export default function ImportExportPie({ pie }) {
  const exportKwh = Number(pie?.exported_kwh)         || 0;
  const selfKwh   = Number(pie?.self_consumption_kwh) || 0;

  if (exportKwh + selfKwh === 0) {
    return <Empty>No solar generation today yet.</Empty>;
  }

  const data = [
    { name: "Exported",         value: exportKwh, fill: EXPORT_COLOR },
    { name: "Self-Consumption", value: selfKwh,   fill: SELF_COLOR }
  ];

  return (
    <div style={{ width: "100%", height: 240 }}>
      <ResponsiveContainer>
        <PieChart>
          <Pie
            data={data}
            dataKey="value"
            nameKey="name"
            innerRadius="55%"
            outerRadius="85%"
            isAnimationActive={false}
          >
            {data.map((slice) => (
              <Cell key={slice.name} fill={slice.fill} stroke="none" />
            ))}
          </Pie>
          <Tooltip
            contentStyle={{
              background: "var(--color-surface-container-high)",
              border: `1px solid ${GRID_COLOR}`,
              color: TEXT_COLOR,
              fontSize: 12
            }}
            formatter={(v, name) => [`${Number(v).toFixed(2)} kWh`, name]}
          />
          <Legend wrapperStyle={{ color: TEXT_COLOR, fontSize: 12 }} />
        </PieChart>
      </ResponsiveContainer>
    </div>
  );
}

function Empty({ children }) {
  return (
    <div className="text-label-md text-on-surface-variant italic py-md">{children}</div>
  );
}
