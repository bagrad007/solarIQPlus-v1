import { Controller } from "@hotwired/stimulus"

/**
 * Ensures Enter in email/password submits the form (implicit submit can be
 * inconsistent with some autofill / IME / Turbo combinations).
 */
export default class extends Controller {
  maybeSubmit(event) {
    if (event.key !== "Enter" || event.repeat) return
    if (event.isComposing) return

    const target = event.target
    if (!(target instanceof HTMLInputElement)) return

    const { type } = target
    if (type !== "email" && type !== "password" && type !== "text") return

    event.preventDefault()
    this.element.requestSubmit()
  }
}
