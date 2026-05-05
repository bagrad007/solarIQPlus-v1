// Tiny SVG renderers for the AI Energy Analyst widget.
//
// Server returns one of three `kind`s; the Stimulus controller calls
// `renderChart(spec)` and inserts the returned SVGElement. Keeping the
// renderers dependency-free (no D3, no Chart.js) avoids growing the JS
// bundle for the demo. If we ever need richer interaction (brushing,
// tooltips, theming), this is the file to upgrade — or replace with a
// React island per the plan.

const SVG_NS = "http://www.w3.org/2000/svg";

const PALETTE = {
  primary: "var(--color-primary)",
  primaryFixed: "var(--color-primary-fixed)",
  secondary: "var(--color-secondary)",
  outline: "var(--color-outline-variant)",
  surface: "var(--color-surface-container-lowest)",
  text: "var(--color-on-surface-variant)",
  marker: "var(--color-error)"
};

export function renderChart(spec) {
  if (!spec || typeof spec !== "object") return placeholder("No data.");

  switch (spec.kind) {
    case "line": return renderLine(spec);
    case "bar":  return renderBar(spec);
    case "dual": return renderDual(spec);
    default:     return placeholder(`Unknown chart kind: ${spec.kind}`);
  }
}

function el(name, attrs = {}, children = []) {
  const node = document.createElementNS(SVG_NS, name);
  for (const [k, v] of Object.entries(attrs)) node.setAttribute(k, v);
  for (const c of children) node.appendChild(c);
  return node;
}

function wrap(spec, svg) {
  const container = document.createElement("figure");
  container.className = "rounded-md border border-outline-variant bg-surface-container-low p-sm mt-sm";
  if (spec.title) {
    const cap = document.createElement("figcaption");
    cap.className = "text-label-sm text-on-surface-variant mb-xs";
    cap.textContent = spec.title;
    container.appendChild(cap);
  }
  container.appendChild(svg);
  return container;
}

function placeholder(message) {
  const div = document.createElement("div");
  div.className = "text-label-sm text-on-surface-variant italic";
  div.textContent = message;
  return div;
}

function scaleLinear(values, range) {
  const min = Math.min(...values);
  const max = Math.max(...values);
  const span = max - min || 1;
  return (v) => range[0] + ((v - min) / span) * (range[1] - range[0]);
}

// --- line chart with optional anomaly markers (efficiency/PR trend) ---
function renderLine(spec) {
  const W = 480, H = 140, PAD = { l: 28, r: 8, t: 8, b: 18 };
  const points = (spec.points || []).slice(0, 120);
  if (points.length === 0) return wrap(spec, blankChart(W, H));

  const xs = points.map((_, i) => i);
  const ys = points.map((p) => Number(p.y));
  const xScale = scaleLinear(xs, [PAD.l, W - PAD.r]);
  const yScale = scaleLinear([Math.min(...ys, 0), Math.max(...ys, 100)], [H - PAD.b, PAD.t]);

  const path = points.map((p, i) => `${i === 0 ? "M" : "L"} ${xScale(i).toFixed(1)} ${yScale(Number(p.y)).toFixed(1)}`).join(" ");

  const svg = el("svg", { viewBox: `0 0 ${W} ${H}`, width: "100%", height: H, role: "img", "aria-label": spec.title || "trend" });
  svg.appendChild(el("rect", { x: 0, y: 0, width: W, height: H, fill: PALETTE.surface }));

  for (const tick of [25, 50, 75, 100]) {
    const y = yScale(tick).toFixed(1);
    svg.appendChild(el("line", { x1: PAD.l, x2: W - PAD.r, y1: y, y2: y, stroke: PALETTE.outline, "stroke-dasharray": "2 3" }));
    const t = el("text", { x: 4, y: y, fill: PALETTE.text, "font-size": 9 });
    t.textContent = `${tick}%`;
    svg.appendChild(t);
  }

  svg.appendChild(el("path", { d: path, fill: "none", stroke: PALETTE.primary, "stroke-width": 2 }));

  for (const m of spec.markers || []) {
    const idx = points.findIndex((p) => p.x === m.x);
    if (idx < 0) continue;
    const x = xScale(idx).toFixed(1);
    svg.appendChild(el("line", { x1: x, x2: x, y1: PAD.t, y2: H - PAD.b, stroke: PALETTE.marker, "stroke-dasharray": "3 3", "stroke-width": 1 }));
    const label = el("text", { x: x, y: PAD.t + 8, fill: PALETTE.marker, "font-size": 9, "text-anchor": "middle" });
    label.textContent = m.label || "";
    svg.appendChild(label);
  }

  appendAxisLabels(svg, points.map((p) => p.x), xScale, H, PAD);

  return wrap(spec, svg);
}

// --- bar chart (fault frequencies, panel rankings) ---
function renderBar(spec) {
  const W = 480, H = 160, PAD = { l: 80, r: 8, t: 8, b: 18 };
  const points = (spec.points || []).slice(0, 10);
  if (points.length === 0) return wrap(spec, blankChart(W, H));

  const max = Math.max(...points.map((p) => Number(p.value)), 1);
  const rowH = (H - PAD.t - PAD.b) / points.length;

  const svg = el("svg", { viewBox: `0 0 ${W} ${H}`, width: "100%", height: H, role: "img", "aria-label": spec.title || "bars" });
  svg.appendChild(el("rect", { x: 0, y: 0, width: W, height: H, fill: PALETTE.surface }));

  points.forEach((p, i) => {
    const y = PAD.t + i * rowH + rowH * 0.15;
    const w = (Number(p.value) / max) * (W - PAD.l - PAD.r);
    svg.appendChild(el("rect", { x: PAD.l, y, width: w.toFixed(1), height: rowH * 0.7, fill: PALETTE.primary, rx: 1 }));

    const label = el("text", { x: PAD.l - 4, y: y + rowH * 0.5, fill: PALETTE.text, "font-size": 10, "text-anchor": "end", "dominant-baseline": "middle" });
    label.textContent = String(p.label);
    svg.appendChild(label);

    const value = el("text", { x: PAD.l + w + 4, y: y + rowH * 0.5, fill: PALETTE.text, "font-size": 10, "dominant-baseline": "middle" });
    value.textContent = String(p.value);
    svg.appendChild(value);
  });

  return wrap(spec, svg);
}

// --- dual line (actual vs expected) ---
function renderDual(spec) {
  const W = 480, H = 160, PAD = { l: 36, r: 8, t: 16, b: 24 };
  const A = (spec.series_a && spec.series_a.points) || [];
  const B = (spec.series_b && spec.series_b.points) || [];
  if (A.length === 0 && B.length === 0) return wrap(spec, blankChart(W, H));

  const allValues = [...A.map((p) => Number(p.y)), ...B.map((p) => Number(p.y))];
  const xs = A.map((_, i) => i);
  const xScale = scaleLinear(xs.length ? xs : [0], [PAD.l, W - PAD.r]);
  const yScale = scaleLinear([Math.min(...allValues, 0), Math.max(...allValues, 1)], [H - PAD.b, PAD.t]);

  const seriesPath = (series) =>
    series.map((p, i) => `${i === 0 ? "M" : "L"} ${xScale(i).toFixed(1)} ${yScale(Number(p.y)).toFixed(1)}`).join(" ");

  const svg = el("svg", { viewBox: `0 0 ${W} ${H}`, width: "100%", height: H, role: "img", "aria-label": spec.title || "dual series" });
  svg.appendChild(el("rect", { x: 0, y: 0, width: W, height: H, fill: PALETTE.surface }));

  if (B.length) svg.appendChild(el("path", { d: seriesPath(B), fill: "none", stroke: PALETTE.outline, "stroke-width": 1.5, "stroke-dasharray": "4 3" }));
  if (A.length) svg.appendChild(el("path", { d: seriesPath(A), fill: "none", stroke: PALETTE.primary, "stroke-width": 2 }));

  const legend = el("g", { transform: `translate(${PAD.l}, 4)` });
  if (spec.series_a) {
    legend.appendChild(swatch(0, PALETTE.primary, spec.series_a.label || "A", false));
  }
  if (spec.series_b) {
    legend.appendChild(swatch(72, PALETTE.outline, spec.series_b.label || "B", true));
  }
  svg.appendChild(legend);

  appendAxisLabels(svg, A.map((p) => p.x), xScale, H, PAD);

  return wrap(spec, svg);
}

function swatch(x, color, label, dashed) {
  const g = el("g", { transform: `translate(${x}, 0)` });
  g.appendChild(el("line", { x1: 0, x2: 14, y1: 6, y2: 6, stroke: color, "stroke-width": 2, "stroke-dasharray": dashed ? "4 3" : "" }));
  const t = el("text", { x: 18, y: 9, fill: PALETTE.text, "font-size": 10 });
  t.textContent = label;
  g.appendChild(t);
  return g;
}

// Sparse axis labels — first, middle, last — to avoid clutter at 30+ days.
function appendAxisLabels(svg, xValues, xScale, H, PAD) {
  if (!xValues.length) return;
  const indices = [0, Math.floor(xValues.length / 2), xValues.length - 1];
  for (const i of indices) {
    const t = el("text", {
      x: xScale(i).toFixed(1),
      y: H - 4,
      fill: PALETTE.text,
      "font-size": 9,
      "text-anchor": i === 0 ? "start" : (i === xValues.length - 1 ? "end" : "middle")
    });
    t.textContent = String(xValues[i]).slice(5); // strip "YYYY-" for compactness
    svg.appendChild(t);
  }
}

function blankChart(W, H) {
  const svg = el("svg", { viewBox: `0 0 ${W} ${H}`, width: "100%", height: H });
  svg.appendChild(el("rect", { x: 0, y: 0, width: W, height: H, fill: PALETTE.surface }));
  const t = el("text", { x: W / 2, y: H / 2, fill: PALETTE.text, "font-size": 11, "text-anchor": "middle" });
  t.textContent = "No data";
  svg.appendChild(t);
  return svg;
}
