import { Controller } from "@hotwired/stimulus";

// Debounced submit for the Alarms filter form. Search input keystrokes call
// `schedule`, which delays form submission by `debounceMs` so we don't hit
// the server on every character. Other controls call `submit` directly.
//
// The Turbo Frame around the alarms table picks up the response and swaps
// only that frame; the toolbar stays mounted, preserving focus + caret.
export default class extends Controller {
  static targets = ["input"];
  static values  = { debounceMs: { type: Number, default: 250 } };

  connect() {
    this.timer = null;
  }

  disconnect() {
    if (this.timer) clearTimeout(this.timer);
  }

  schedule() {
    if (this.timer) clearTimeout(this.timer);
    this.timer = setTimeout(() => this.submit(), this.debounceMsValue);
  }

  submit() {
    if (this.timer) {
      clearTimeout(this.timer);
      this.timer = null;
    }
    this.element.requestSubmit();
  }
}
