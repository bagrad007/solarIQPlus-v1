// Live Energy Topology panel. Pure presentation: takes the energy_flow slice
// from SiteDiagnostics and renders an industrial topology diagram (Solar /
// Grid / Battery / House as filled-circle "stations" connected by dashed
// accent-color conductors) plus a column of four metric tiles.
//
// Visual language is borrowed from a reference design the user supplied:
//   - Filled light-color circle badges with bold filled-variant icons
//   - House station is larger with a thick primary ring (focal recipient)
//   - Conductors are straight dashed lines in the source-node's accent color
//   - All three conductors converge at a central hub point; the vertical
//     Solar→House conductor extends through that hub down to the House badge
//
// This is a snapshot of the latest telemetry reading — refreshed only when
// the page is reloaded.

// ── Color tokens ──────────────────────────────────────────────────────────
// Sourced from app/assets/stylesheets/application.tailwind.css. The
// solar-accent token is *reserved* for solar-domain highlights — this panel
// is the canonical home for it.
//
// Each station has a (badgeBg, iconColor) pair styled like a "lit-up button":
// pale tinted background + bold same-hue icon. The pale backgrounds are
// either existing M3 *-fixed tokens (which are already light tints of the
// accent) or color-mix() against white where no -fixed token exists.
const STATION = {
  solar: {
    badgeBg:   "color-mix(in srgb, var(--color-solar-accent) 18%, white)",
    icon:      "var(--color-solar-accent)",
    line:      "var(--color-solar-accent)"
  },
  grid: {
    badgeBg:   "var(--color-primary-fixed)",
    icon:      "var(--color-primary)",
    line:      "var(--color-primary)"
  },
  // No green token in our palette yet. When battery telemetry comes online
  // we should add `--color-battery-{bg,icon}` to the stylesheet; until then
  // the muted treatment is correct (we render Battery as "Not installed").
  battery: {
    badgeBg:   "var(--color-surface-container-high)",
    icon:      "var(--color-on-surface-variant)",
    line:      "var(--color-on-surface-variant)"
  },
  house: {
    badgeBg:   "var(--color-surface-container-highest)",
    icon:      "var(--color-primary)",
    ring:      "var(--color-primary)"        // thick border identifies the recipient
  }
};
const COLOR = {
  error: "var(--color-error)",               // overrides Grid line when importing
  faint: "var(--color-outline-variant)",
  muted: "var(--color-on-surface-variant)"
};

// ── Layout (SVG viewBox 480×480) ─────────────────────────────────────────
// Cross topology: Solar top, Grid left, Battery right, House bottom.
// Coordinates are CENTERS of each station badge. All four stations render
// labels BELOW the badge for visual consistency.
//
// The square viewBox leaves headroom both below Solar's badge (for Solar's
// labels — see SOLAR_LABEL_RESERVED_VBU below) and below House's badge
// (for House's labels) so neither set of text ever overlaps a conductor.
const VIEW_W = 480;
const VIEW_H = 480;
// Source nodes (Solar/Grid/Battery) are 80 px badges; House is 96 px — a
// 1.2× proportional bump that matches the reference design and gives House
// quiet visual primacy without dwarfing the others. The thick primary
// border on House does the rest of the focal-point work.
const NODE = {
  solar:   { cx: 240, cy: 110, r: 40 },
  grid:    { cx: 70,  cy: 240, r: 40 },
  battery: { cx: 410, cy: 240, r: 40 },
  house:   { cx: 240, cy: 370, r: 48 }
};

// Conductors — straight dashed lines that converge at a central hub point.
// Each line ends at the EDGE of the source/destination badge.
//
// The Solar→House line is intentionally CUT BACK at the top: instead of
// starting at the Solar badge's bottom edge (y = solar.cy + solar.r), it
// starts a few viewBox units below the label stack so the dashed line does
// not pass through "X kW / SOLAR". Keep this tight to the real label height
// (HTML below the badge) — an oversized gap reads as a broken diagram on
// large viewports where the panel hits max-width and scales 1:1.
const HUB_Y = 240;
const SOLAR_LABEL_RESERVED_VBU = 46;     // viewBox gap ≈ label block + small margin
const PIPE = {
  solar_to_house:   `M 240 ${NODE.solar.cy + NODE.solar.r + SOLAR_LABEL_RESERVED_VBU} V ${NODE.house.cy - NODE.house.r}`,
  grid_to_hub:      `M ${NODE.grid.cx + NODE.grid.r} ${HUB_Y} H 240`,
  battery_to_hub:   `M ${NODE.battery.cx - NODE.battery.r} ${HUB_Y} H 240`
};

export default function EnergyFlowPanel({ flow }) {
  const f = flow || {};
  const importing  = f.grid_w != null && f.grid_w < 0;
  const exporting  = f.grid_w != null && f.grid_w > 0;
  const hasBattery = f.battery_w != null;

  return (
    <div className="flex flex-col gap-md">
      {/* 2:1 split — diagram dominates, metrics column is condensed.
          Splits at `md` (768 px) so the side-by-side layout holds across
          typical desktop content widths even when a sidebar is present. */}
      <div className="grid grid-cols-1 md:grid-cols-[minmax(0,2fr)_minmax(0,1fr)] gap-xl items-center">
        <FlowDiagram flow={f} importing={importing} exporting={exporting} hasBattery={hasBattery} />
        <FlowMetrics flow={f} />
      </div>
    </div>
  );
}

// ── Diagram ───────────────────────────────────────────────────────────────
function FlowDiagram({ flow, importing, exporting, hasBattery }) {
  const solarActive   = flow.solar_w > 0;
  const houseActive   = flow.house_w > 0;
  const gridActive    = importing || exporting;
  const batteryActive = hasBattery && flow.battery_w !== 0;

  // Grid line color: importing reads as a fault/cost (red), exporting as a
  // surplus (primary navy — our positive-good color, matches solar-net tile).
  const gridLineColor = importing ? COLOR.error : STATION.grid.line;

  return (
    <div
      className="relative mx-auto w-full"
      style={{ maxWidth: VIEW_W, aspectRatio: `${VIEW_W} / ${VIEW_H}` }}
    >
      {/* Conductors (SVG, fills the container). pointer-events-none so the
          badges underneath stay interactive if we ever attach hovers. */}
      <svg
        viewBox={`0 0 ${VIEW_W} ${VIEW_H}`}
        preserveAspectRatio="xMidYMid meet"
        className="absolute inset-0 w-full h-full pointer-events-none"
        aria-hidden="true"
      >
        <Conductor
          d={PIPE.solar_to_house}
          color={solarActive ? STATION.solar.line : COLOR.faint}
          active={solarActive}
        />
        <Conductor
          d={PIPE.grid_to_hub}
          color={gridActive ? gridLineColor : COLOR.faint}
          active={gridActive}
        />
        {hasBattery && (
          <Conductor
            d={PIPE.battery_to_hub}
            color={batteryActive ? STATION.battery.line : COLOR.faint}
            active={batteryActive}
          />
        )}
      </svg>

      {/* Stations (HTML, positioned by viewBox-fraction percentages). All
          stations render labels below their badge; the Solar→House
          conductor is cut back at the top (see SOLAR_LABEL_RESERVED_VBU)
          so it doesn't pass through Solar's text. */}
      <Station
        node={NODE.solar}
        chrome={STATION.solar}
        icon="solar_power"
        label="Solar"
        watts={flow.solar_w}
      />
      <Station
        node={NODE.grid}
        chrome={importing ? { ...STATION.grid, icon: COLOR.error, badgeBg: "var(--color-error-container)" } : STATION.grid}
        icon="bolt"
        label="Grid"
        watts={flow.grid_w}
        signed
      />
      <Station
        node={NODE.battery}
        chrome={STATION.battery}
        icon="battery_charging_full"
        label="Battery"
        watts={flow.battery_w}
        sublabel={hasBattery ? null : "Not installed"}
        muted={!hasBattery}
      />
      <Station
        node={NODE.house}
        chrome={STATION.house}
        icon="home"
        label="House"
        watts={flow.house_w}
        ring={STATION.house.ring}
        emphasized
      />
    </div>
  );
}

// ── Station badge ─────────────────────────────────────────────────────────
// Filled circle in the station's tinted background color, with a bold
// filled-variant Material Symbol icon centered inside. Watt readout and
// label text sit BELOW the circle.
//
// `ring` adds a thick same-color border (used on the House badge to mark it
// as the focal recipient — matches the reference design).
function Station({ node, chrome, icon, label, watts, sublabel, signed, muted, ring, emphasized }) {
  const display = formatPower(watts, { signed });
  const leftPct = (node.cx / VIEW_W) * 100;
  const topPct  = ((node.cy - node.r) / VIEW_H) * 100;
  const diameter = node.r * 2;

  return (
    <div
      className="absolute flex flex-col items-center"
      style={{
        left:      `${leftPct.toFixed(2)}%`,
        top:       `${topPct.toFixed(2)}%`,
        transform: "translateX(-50%)",
        opacity:   muted ? 0.55 : 1,
        zIndex:    1
      }}
    >
      <div
        className="flex items-center justify-center rounded-full"
        style={{
          width:      diameter,
          height:     diameter,
          background: chrome.badgeBg,
          border:     ring ? `4px solid ${ring}` : "none",
          boxShadow:  emphasized
            ? "0 8px 24px rgba(0, 31, 81, 0.18)"
            : "0 2px 6px rgba(0, 0, 0, 0.06)"
        }}
      >
        <span
          className="material-symbols-outlined"
          style={{
            fontSize: emphasized ? 44 : 36,
            color: chrome.icon,
            // Filled variant — matches the reference's solid icon look and
            // makes the station read as a "lit indicator", not an outline.
            fontVariationSettings: "'FILL' 1, 'wght' 500, 'GRAD' 0, 'opsz' 24"
          }}
        >
          {icon}
        </span>
      </div>

      <div className="flex flex-col items-center mt-1.5 gap-0.5" style={{ lineHeight: 1.2 }}>
        <span
          className="text-label-md"
          style={{
            color: "var(--color-on-surface)",
            fontWeight: 700,
            fontVariantNumeric: "tabular-nums",
            whiteSpace: "nowrap"
          }}
        >
          {display}
        </span>
        <span
          className="text-label-sm uppercase"
          style={{ color: COLOR.muted, letterSpacing: "0.06em" }}
        >
          {label}
        </span>
        {sublabel && (
          <span className="text-label-sm italic" style={{ color: COLOR.muted }}>
            {sublabel}
          </span>
        )}
      </div>
    </div>
  );
}

// ── Conductor (single dashed line) ────────────────────────────────────────
function Conductor({ d, color, active }) {
  return (
    <path
      d={d}
      stroke={color}
      strokeWidth={active ? 2.5 : 1.5}
      strokeDasharray="8 6"
      strokeLinecap="round"
      fill="none"
      opacity={active ? 0.85 : 0.4}
    />
  );
}

// ── Right column: metric tiles ────────────────────────────────────────────
function FlowMetrics({ flow }) {
  const netW = flow.solar_net_w;
  const netLabel = netW == null ? "Solar net" : netW < 0 ? "Solar deficit" : "Solar surplus";
  const netTone  = netW == null ? "neutral" : netW < 0 ? "error" : "primary";
  // The label already conveys direction (deficit / surplus) — showing a minus
  // sign on top of "deficit" is double-negation. Display absolute magnitude.
  const netDisplay = netW == null ? null : Math.abs(netW);

  return (
    <div className="flex flex-col gap-sm">
      <Tile label="Self-sufficiency"   value={formatPct(flow.self_sufficiency_pct)} tone="primary" />
      <Tile label="Self-consumption"   value={formatPct(flow.self_consumption_pct)} tone="primary" />
      <Tile
        label="Battery state of charge"
        value={formatPct(flow.battery_soc_pct)}
        sublabel="Not installed"
        tone="muted"
      />
      <Tile label={netLabel} value={formatPower(netDisplay)} tone={netTone} />
    </div>
  );
}

function Tile({ label, value, sublabel, tone }) {
  const valueColor =
    tone === "primary" ? "var(--color-primary)" :
    tone === "error"   ? "var(--color-error)"   :
                         "var(--color-on-surface)";
  return (
    <div
      className="flex items-baseline justify-between gap-sm px-sm py-xs rounded-md"
      style={{ background: "var(--color-surface-container-high)" }}
    >
      <div className="flex flex-col">
        <span className="text-label-sm" style={{ color: COLOR.muted }}>{label}</span>
        {sublabel && (
          <span className="text-label-sm italic" style={{ color: COLOR.muted }}>{sublabel}</span>
        )}
      </div>
      <span
        className="text-title-md"
        style={{
          color: tone === "muted" ? COLOR.muted : valueColor,
          fontVariantNumeric: "tabular-nums"
        }}
      >
        {value}
      </span>
    </div>
  );
}

// ── Formatters ────────────────────────────────────────────────────────────
// Display in kW once the magnitude crosses 1 kW; W otherwise. Matches the
// reference design (which shows 3.4 kW, 0.2 kW, etc.) and avoids the eye-
// glazing 6-digit watt readouts we had before (e.g. "109,060 W" → "109 kW").
function formatPower(value, { signed = false } = {}) {
  if (value == null) return "—";
  const sign = signed && value > 0 ? "+" : "";
  const abs  = Math.abs(value);
  if (abs >= 1000) {
    const kw = value / 1000;
    return `${sign}${kw.toFixed(kw >= 100 ? 0 : 1)} kW`;
  }
  return `${sign}${Math.round(value).toLocaleString()} W`;
}

function formatPct(value) {
  if (value == null) return "—";
  return `${Number(value).toFixed(value >= 10 ? 0 : 1)} %`;
}
