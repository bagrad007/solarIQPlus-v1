// Mount point for the Diagnostics React island. The ERB view renders a
// `<div data-diagnostics-mount data-payload="{...json...}">` placeholder; this
// entry script finds every such div on the page (just one in practice) and
// attaches a React root populated from its data-payload attribute.
//
// We listen for both `DOMContentLoaded` (normal full-page load) and
// `turbo:load` (Turbo Drive navigation), and we track which mount points have
// already been rendered so a repeat event doesn't double-mount.

import { createRoot } from "react-dom/client";
import DiagnosticsPage from "./DiagnosticsPage.jsx";

const MOUNTED = new WeakSet();

function mountAll() {
  document.querySelectorAll("[data-diagnostics-mount]").forEach((node) => {
    if (MOUNTED.has(node)) return;
    // Mark first so a downstream render error can't re-trigger createRoot on
    // the same container on the next DOMContentLoaded / turbo:load event.
    MOUNTED.add(node);
    let payload;
    try {
      payload = JSON.parse(node.dataset.payload || "{}");
    } catch (err) {
      console.error("[diagnostics] failed to parse data-payload", err);
      return;
    }
    const root = createRoot(node);
    root.render(<DiagnosticsPage payload={payload} />);
  });
}

document.addEventListener("DOMContentLoaded", mountAll);
document.addEventListener("turbo:load", mountAll);
