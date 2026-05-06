// Mirrors `sites/_forecast_tile.html.erb` for the diagnostics island (same
// data-attributes as the ERB partial for design / contract tests).

const WEATHER_ICONS = {
  sunny: "wb_sunny",
  partly_cloudy: "partly_cloudy_day",
  cloudy: "cloud",
  foggy: "foggy",
  rain: "rainy",
  snow: "ac_unit",
  thunderstorm: "thunderstorm",
  unknown: "help"
};

function formatProjectedKwh(n) {
  if (n == null || Number.isNaN(Number(n))) return "—";
  return Number(n).toLocaleString(undefined, { minimumFractionDigits: 0, maximumFractionDigits: 1 });
}

function dataProjectedAttr(n) {
  if (n == null || Number.isNaN(Number(n))) return "—";
  return String(Number(n).toFixed(1)).replace(/\.0$/, "");
}

export default function ForecastTile({ label, projectedKwh, condition, highF }) {
  const cond = condition && String(condition).length ? String(condition) : "unknown";
  const icon = WEATHER_ICONS[cond] || WEATHER_ICONS.unknown;
  const display = formatProjectedKwh(projectedKwh);
  const hasKwh = projectedKwh != null && !Number.isNaN(Number(projectedKwh));

  return (
    <div
      className="rounded-lg border border-outline-variant bg-surface-container-lowest p-md"
      data-forecast-tile
      data-projected-kwh={dataProjectedAttr(projectedKwh)}
      data-condition={cond}
    >
      <div className="flex items-start justify-between gap-sm">
        <div className="text-label-sm uppercase text-on-surface-variant">{label}</div>
        <span className="material-symbols-outlined shrink-0 text-solar-accent" style={{ fontSize: 24 }} aria-hidden>
          {icon}
        </span>
      </div>
      <div className="mt-xs text-display-sm text-primary">
        {display}
        {hasKwh ? <span className="ml-xs text-headline-sm font-medium text-on-surface-variant">kWh</span> : null}
      </div>
      <div className="mt-xs text-label-sm capitalize text-on-surface-variant">{cond.replace(/_/g, " ")}</div>
      {highF != null && !Number.isNaN(Number(highF)) ? (
        <div className="mt-xs text-label-sm text-on-surface-variant">
          Daily high {Number(highF).toLocaleString(undefined, { maximumFractionDigits: 1, minimumFractionDigits: 0 })} °F
        </div>
      ) : null}
    </div>
  );
}
