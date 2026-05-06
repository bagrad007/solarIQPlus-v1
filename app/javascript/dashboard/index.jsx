// Mount point for the Dashboard React island. Mirrors the Diagnostics island
// pattern: ERB renders `<div data-dashboard-mount data-payload="{...}">` and
// this entry script attaches a single React root that owns the three chart
// sections (time-series, gauges, pie). Everything else on the page is ERB.

import { createRoot } from "react-dom/client";
import DashboardCharts from "./DashboardCharts.jsx";

const MOUNTED = new WeakSet();

function mountAll() {
  document.querySelectorAll("[data-dashboard-mount]").forEach((node) => {
    if (MOUNTED.has(node)) return;
    // Mark before render so a thrown render error can't re-trigger
    // createRoot on the next DOMContentLoaded / turbo:load event.
    MOUNTED.add(node);
    let payload;
    try {
      payload = JSON.parse(node.dataset.payload || "{}");
    } catch (err) {
      console.error("[dashboard] failed to parse data-payload", err);
      return;
    }
    const root = createRoot(node);
    root.render(<DashboardCharts payload={payload} />);
  });
}

document.addEventListener("DOMContentLoaded", mountAll);
document.addEventListener("turbo:load", mountAll);
