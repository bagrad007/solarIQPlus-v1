// Entry point for the build script in your package.json
import "@hotwired/turbo-rails"
import "./controllers"

// Recharts adds tabindex="0" to its wrapper <div>, surface <svg>, and to
// individual interactive sectors/curves/bars for keyboard a11y. The default
// browser focus indicator picks up the OS accent color (orange on macOS),
// which clashes with our M3 palette. We strip the tabindex so focus never
// triggers. CSS in application.tailwind.css covers any focus state we miss.
function stripRechartsFocus(root = document) {
  root.querySelectorAll(
    '.recharts-wrapper[tabindex], .recharts-surface[tabindex], [class*="recharts-"][tabindex]'
  ).forEach((el) => el.removeAttribute("tabindex"));
}

const rechartsObserver = new MutationObserver((mutations) => {
  for (const m of mutations) {
    for (const node of m.addedNodes) {
      if (node.nodeType !== Node.ELEMENT_NODE) continue;
      stripRechartsFocus(node);
    }
  }
});

document.addEventListener("DOMContentLoaded", () => {
  stripRechartsFocus();
  rechartsObserver.observe(document.body, { childList: true, subtree: true });
});
document.addEventListener("turbo:load", () => stripRechartsFocus());
