// Horizontal bar + large numeric readout (industrial telemetry density).

const TRACK = "var(--color-surface-container-high)";
const LABEL = "var(--color-on-surface-variant)";

export default function GenerationGauge({ label, gauge, accent = "solar" }) {
  const current = Number(gauge?.current_kw) || 0;
  const max = Number(gauge?.max_kw) || Math.max(current, 1);
  const pct = Math.min(100, Math.max(0, (current / max) * 100));
  const fillClass = accent === "primary" ? "bg-primary-container" : "bg-secondary-container";

  const icon = accent === "primary" ? "bolt" : "solar_power";

  return (
    <div className="flex h-full min-h-0 min-w-0 w-full flex-col justify-start rounded-xl border border-outline-variant bg-surface-container-lowest px-md py-sm motion-safe:animate-[dashboard-reveal_0.5s_ease-out_both]">
      <div className="mb-xs flex min-h-[1.5rem] items-center gap-sm">
        <span
          className={`material-symbols-outlined shrink-0 text-[20px] leading-none ${accent === "primary" ? "text-primary/80" : "text-solar-accent/85"}`}
          style={{ fontVariationSettings: "'FILL' 1, 'wght' 500, 'GRAD' 0, 'opsz' 24" }}
          aria-hidden
        >
          {icon}
        </span>
        <p className="min-w-0 flex-1 text-label-sm font-semibold uppercase leading-snug tracking-wide" style={{ color: LABEL }}>
          {label}
        </p>
      </div>
      <div className="flex items-baseline gap-sm flex-wrap">
        <span
          className={`font-[family-name:var(--font-display-serif)] text-headline-lg tracking-tight ${accent === "primary" ? "text-primary-container" : "text-secondary"}`}
        >
          {current.toFixed(1)}
        </span>
        <span className="text-headline-md text-on-surface-variant font-medium">kW</span>
      </div>
      <div className="mt-xs w-full h-1 rounded-full overflow-hidden" style={{ background: TRACK }}>
        <div
          className={`h-full rounded-full transition-[width] duration-500 ease-out ${fillClass}`}
          style={{ width: `${pct}%` }}
        />
      </div>
      <p className="mt-xs text-label-sm text-on-surface-variant">
        of {max.toFixed(0)} kW nameplate
      </p>
    </div>
  );
}
