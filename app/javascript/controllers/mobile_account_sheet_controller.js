import { Controller } from "@hotwired/stimulus";

// Toggles the mobile account sheet (identity + Sign out) anchored above
// the mobile bottom nav. The sheet uses the HTML5 `hidden` attribute as
// its source of truth; `aria-expanded` on the avatar button mirrors it
// for screen readers. Closes on tap-outside and on Escape.
export default class extends Controller {
  static targets = ["button", "sheet"];

  connect() {
    this.onDocClick = this.onDocClick.bind(this);
    this.onKeydown = this.onKeydown.bind(this);
    document.addEventListener("click", this.onDocClick);
    document.addEventListener("keydown", this.onKeydown);
  }

  disconnect() {
    document.removeEventListener("click", this.onDocClick);
    document.removeEventListener("keydown", this.onKeydown);
  }

  toggle(event) {
    event?.stopPropagation();
    this.isOpen() ? this.close() : this.open();
  }

  open() {
    this.sheetTarget.hidden = false;
    this.buttonTarget.setAttribute("aria-expanded", "true");
  }

  close() {
    this.sheetTarget.hidden = true;
    this.buttonTarget.setAttribute("aria-expanded", "false");
  }

  isOpen() {
    return !this.sheetTarget.hidden;
  }

  onDocClick(event) {
    if (!this.isOpen()) return;
    if (this.element.contains(event.target)) return;
    this.close();
  }

  onKeydown(event) {
    if (event.key === "Escape" && this.isOpen()) this.close();
  }
}
