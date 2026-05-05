import { Controller } from "@hotwired/stimulus";
import { renderChart } from "../energy_analyst/charts";

// Floating chat widget for the AI Energy Analyst demo.
//
// Responsibilities (deliberately narrow — no global state, no router
// awareness): toggle the panel, manage in-memory message history for the
// session, post user messages to the demo endpoint, render assistant
// replies (markdown-light) and inline SVG charts.
//
// Data attributes (set by `_ai_energy_analyst_widget.html.erb`):
//   data-ai-energy-analyst-url-value     POST endpoint
//   data-ai-energy-analyst-csrf-value    CSRF token (read once)
//   data-ai-energy-analyst-context-value short label for the panel header
export default class extends Controller {
  static targets = ["panel", "fab", "messages", "input", "form", "starters", "send"];
  static values = {
    url: String,
    csrf: String,
    context: { type: String, default: "Customer" }
  };
  static classes = ["open"];

  connect() {
    this.isOpen = false;
    this.pending = false;
    this.history = [];
    this.greet();
  }

  toggle() {
    this.isOpen ? this.close() : this.open();
  }

  open() {
    this.isOpen = true;
    this.panelTarget.dataset.open = "true";
    // The panel stays `display: flex` always — toggling `hidden` would break
    // the flex column layout (children would stack as blocks). We hide
    // visually with opacity + scale and disable pointer events instead.
    this.panelTarget.classList.remove("scale-95", "opacity-0", "pointer-events-none");
    this.panelTarget.classList.add("scale-100", "opacity-100");
    requestAnimationFrame(() => this.inputTarget.focus());
  }

  close() {
    this.isOpen = false;
    this.panelTarget.dataset.open = "false";
    this.panelTarget.classList.add("scale-95", "opacity-0", "pointer-events-none");
    this.panelTarget.classList.remove("scale-100", "opacity-100");
  }

  starter(event) {
    const text = event.currentTarget.dataset.prompt;
    if (!text) return;
    this.inputTarget.value = text;
    this.submit();
  }

  submit(event) {
    if (event) event.preventDefault();
    const text = (this.inputTarget.value || "").trim();
    if (!text || this.pending) return;
    this.inputTarget.value = "";
    this.send(text);
  }

  // --- internals ---

  greet() {
    this.appendMessage({
      role: "assistant",
      text: `Hi — I'm your AI Energy Analyst for ${this.contextValue}. Ask about efficiency, anomalies, faults, or maintenance, or pick a starter below.`,
      visualizations: [],
      timestamp: new Date()
    });
  }

  send(text) {
    this.appendMessage({ role: "user", text, visualizations: [], timestamp: new Date() });
    this.hideStarters();
    this.setPending(true);

    fetch(this.urlValue, {
      method: "POST",
      credentials: "same-origin",
      headers: {
        "Content-Type": "application/json",
        "Accept": "application/json",
        "X-CSRF-Token": this.csrfValue
      },
      body: JSON.stringify({ message: text })
    })
      .then((res) => {
        if (!res.ok) throw new Error(`Server returned ${res.status}`);
        return res.json();
      })
      .then((payload) => this.deliverWithTypingDelay(payload))
      .catch((err) => {
        this.setPending(false);
        this.appendMessage({
          role: "assistant",
          text: `I hit an error reaching the analyst service (${err.message}). Try again in a moment.`,
          visualizations: [],
          timestamp: new Date(),
          variant: "error"
        });
      });
  }

  // The mock backend is instant; pretend it's thinking for 400-900ms so
  // the UI feels like an LLM and gives the user time to register the
  // typing indicator. Tunable here only — no backend coupling.
  deliverWithTypingDelay(payload) {
    const delay = 400 + Math.random() * 500;
    setTimeout(() => {
      this.setPending(false);
      this.appendMessage({
        role: "assistant",
        text: payload.reply_text || "(no reply)",
        visualizations: payload.visualizations || [],
        timestamp: new Date()
      });
    }, delay);
  }

  setPending(value) {
    this.pending = value;
    this.sendTarget.disabled = value;
    this.inputTarget.disabled = value;
    if (value) {
      this.appendTypingIndicator();
    } else {
      this.removeTypingIndicator();
    }
  }

  appendTypingIndicator() {
    const wrap = document.createElement("div");
    wrap.dataset.typingIndicator = "true";
    wrap.className = "flex items-center gap-xs px-md py-sm";
    wrap.innerHTML = `
      <span class="material-symbols-outlined text-on-surface-variant" style="font-size: 18px;">smart_toy</span>
      <span class="inline-flex gap-1">
        <span class="w-1.5 h-1.5 rounded-full bg-on-surface-variant animate-pulse"></span>
        <span class="w-1.5 h-1.5 rounded-full bg-on-surface-variant animate-pulse" style="animation-delay: 150ms"></span>
        <span class="w-1.5 h-1.5 rounded-full bg-on-surface-variant animate-pulse" style="animation-delay: 300ms"></span>
      </span>
    `;
    this.messagesTarget.appendChild(wrap);
    this.scrollToBottom();
  }

  removeTypingIndicator() {
    const node = this.messagesTarget.querySelector('[data-typing-indicator="true"]');
    if (node) node.remove();
  }

  hideStarters() {
    if (!this.hasStartersTarget) return;
    this.startersTarget.classList.add("hidden");
  }

  appendMessage({ role, text, visualizations, timestamp, variant }) {
    this.history.push({ role, text, timestamp });

    const row = document.createElement("div");
    row.className = `flex flex-col ${role === "user" ? "items-end" : "items-start"} gap-1 px-md`;

    const bubble = document.createElement("div");
    const isError = variant === "error";
    const base = "max-w-[88%] rounded-lg px-md py-sm text-body-md whitespace-pre-line";
    const palette = role === "user"
      ? "bg-primary text-on-primary"
      : isError
        ? "bg-error-container text-on-error-container"
        : "bg-surface-container text-on-surface";
    bubble.className = `${base} ${palette}`;
    bubble.textContent = text;
    row.appendChild(bubble);

    for (const spec of visualizations || []) {
      const chart = renderChart(spec);
      chart.classList.add("w-full", "max-w-[88%]");
      row.appendChild(chart);
    }

    const meta = document.createElement("span");
    meta.className = "text-label-sm text-on-surface-variant";
    meta.textContent = timestamp.toLocaleTimeString([], { hour: "numeric", minute: "2-digit" });
    row.appendChild(meta);

    this.messagesTarget.appendChild(row);
    this.scrollToBottom();
  }

  scrollToBottom() {
    requestAnimationFrame(() => {
      this.messagesTarget.scrollTop = this.messagesTarget.scrollHeight;
    });
  }
}
