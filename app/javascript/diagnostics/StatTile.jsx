// Single number tile — used for both the "Today" stats and the "Last 7 Days"
// totals. The `tone` prop drives only the color of the number; the surface
// styling stays uniform across all tiles so the page reads as a quiet grid
// of facts rather than a status board.

const TONE_TEXT_CLASS = {
  primary: "text-primary",
  error:   "text-error",
  warn:    "text-secondary",
  neutral: "text-on-surface"
};

export default function StatTile({ label, value, unit, tone = "neutral", large = false }) {
  const toneClass = TONE_TEXT_CLASS[tone] || TONE_TEXT_CLASS.neutral;
  const valueClass = large ? "text-display-lg" : "text-display-md";
  const display = formatValue(value);

  return (
    <div className="flex h-full min-h-[100px] min-w-0 w-full flex-col justify-center rounded-xl border border-outline-variant bg-surface-container-lowest p-md shadow-sm">
      <div className="text-label-sm text-on-surface-variant uppercase tracking-wide">{label}</div>
      <div className={`font-[family-name:var(--font-display-serif)] ${valueClass} ${toneClass} mt-xs tracking-tight`}>
        {display}
        {display !== "—" && (
          <span className="text-headline-md text-on-surface-variant ml-xs">{unit}</span>
        )}
      </div>
    </div>
  );
}

function formatValue(value) {
  if (value == null || Number.isNaN(value)) return "—";
  // Show one decimal for values < 100, integer otherwise — matches the mock's
  // 1.07 MWh / 13.1 kWh / 487 kWh / 104.0 °F density choices.
  const n = Number(value);
  if (Math.abs(n) < 100) return n.toFixed(1);
  return Math.round(n).toLocaleString();
}
