// Part-to-whole view of today's exported vs self-consumed solar (kWh).
// Replaces a pie/donut with a proportional ribbon + dual ledger so proportions
// stay scannable on narrow diagnostics cards.

const EXPORT_COLOR = "var(--color-primary)";
const SELF_COLOR = "var(--color-tertiary)";

export default function TodayEnergyMix({ pie }) {
  const exportKwh = Number(pie?.exported_kwh) || 0;
  const selfKwh = Number(pie?.self_consumption_kwh) || 0;
  const total = exportKwh + selfKwh;

  if (total === 0) {
    return <Empty>No solar generation today yet.</Empty>;
  }

  const exportPct = (exportKwh / total) * 100;
  const selfPct = (selfKwh / total) * 100;

  return (
    <div
      className="motion-safe:animate-[dashboard-reveal_0.5s_ease-out_both] flex w-full min-w-0 flex-col gap-md"
      role="group"
      aria-label={`Solar dispatch today: ${exportPct.toFixed(0)} percent exported, ${selfPct.toFixed(
        0
      )} percent self-consumed, ${total.toFixed(2)} kilowatt-hours total.`}
    >
      <div className="flex flex-col gap-xs">
        <div className="flex items-baseline justify-between gap-sm text-label-sm text-on-surface-variant">
          <span>Dispatch mix</span>
          <span className="tabular-nums">{total.toFixed(2)} kWh total</span>
        </div>

        <div
          className="relative flex h-4 w-full min-w-0 overflow-hidden rounded-full bg-surface-container-highest shadow-[inset_0_1px_2px_rgba(0,0,0,0.06)] ring-1 ring-inset ring-outline-variant/40 dark:shadow-[inset_0_1px_2px_rgba(255,255,255,0.04)] dark:ring-white/10"
          aria-hidden
        >
          <div
            className="h-full shrink-0 transition-[width] duration-700 ease-[cubic-bezier(0.22,1,0.36,1)] motion-reduce:transition-none"
            style={{
              width: `${exportPct}%`,
              background: EXPORT_COLOR,
              boxShadow: "inset 0 -1px 0 rgba(0,0,0,0.12)"
            }}
          />
          <div
            className="h-full shrink-0 transition-[width] duration-700 ease-[cubic-bezier(0.22,1,0.36,1)] motion-reduce:transition-none"
            style={{
              width: `${selfPct}%`,
              background: SELF_COLOR,
              boxShadow: "inset 0 -1px 0 rgba(0,0,0,0.15)"
            }}
          />
        </div>
      </div>

      <div className="grid min-w-0 grid-cols-1 gap-sm sm:grid-cols-2 sm:gap-md">
        <LedgerBlock
          icon="cell_tower"
          label="Exported"
          kwh={exportKwh}
          pct={exportPct}
          accent="primary"
          style={{ animationDelay: "0.05s" }}
        />
        <LedgerBlock
          icon="home"
          label="Self-consumption"
          kwh={selfKwh}
          pct={selfPct}
          accent="tertiary"
          style={{ animationDelay: "0.1s" }}
        />
      </div>
    </div>
  );
}

function LedgerBlock({ icon, label, kwh, pct, accent, style }) {
  const bar =
    accent === "primary"
      ? "bg-primary"
      : "bg-tertiary";
  const iconTint = accent === "primary" ? "text-primary/85" : "text-tertiary/90";

  return (
    <article
      className="motion-safe:animate-[dashboard-reveal_0.45s_ease-out_both] relative min-w-0 overflow-hidden rounded-xl border border-outline-variant/70 bg-surface-container-low px-md py-sm"
      style={style}
    >
      <div className={`pointer-events-none absolute inset-y-3 left-0 w-1 rounded-full ${bar}`} aria-hidden />
      <div className="pl-sm">
        <div className="mb-xs flex items-center gap-sm">
          <span
            className={`material-symbols-outlined shrink-0 text-[20px] leading-none ${iconTint}`}
            style={{ fontVariationSettings: "'FILL' 0, 'wght' 500, 'GRAD' 0, 'opsz' 24" }}
            aria-hidden
          >
            {icon}
          </span>
          <span className="min-w-0 text-label-sm font-semibold uppercase tracking-wide text-on-surface-variant">
            {label}
          </span>
        </div>
        <p className="font-[family-name:var(--font-display-serif)] text-headline-lg tabular-nums tracking-tight text-on-surface">
          {kwh.toFixed(2)}
          <span className="ml-xs text-label-md font-medium text-on-surface-variant">kWh</span>
        </p>
        <p className="mt-xs text-label-sm tabular-nums text-on-surface-variant">
          <span className="rounded-full bg-surface-container-high px-sm py-0.5 font-semibold text-on-surface">
            {pct.toFixed(1)}%
          </span>
          <span className="ml-xs">{`of today's solar`}</span>
        </p>
      </div>
    </article>
  );
}

function Empty({ children }) {
  return (
    <div className="motion-safe:animate-[dashboard-reveal_0.45s_ease-out_both] py-md text-label-md italic text-on-surface-variant">
      {children}
    </div>
  );
}
