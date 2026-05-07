import { Controller } from "@hotwired/stimulus";

// Demo: POST the AI brief to Rails and paste the templated draft into the
// report body textarea (same template as ScheduledReport.build_draft_preview_body).

export default class extends Controller {
  static targets = ["brief", "body", "status"];
  static values = { url: String, exampleBrief: String };

  loadExample(event) {
    event.preventDefault();
    if (!this.exampleBriefValue) return;
    this.briefTarget.value = this.exampleBriefValue;
    this.setStatus("Example brief loaded — click Generate draft from brief to fill the body.", false);
    this.briefTarget.focus();
  }

  async generate(event) {
    event.preventDefault();
    const prompt = this.briefTarget.value.trim();
    if (!prompt) {
      this.setStatus("Add an AI brief first.", true);
      return;
    }

    this.setStatus("Generating…", false);
    const token = document.querySelector('meta[name="csrf-token"]')?.getAttribute("content");
    const params = new URLSearchParams();
    if (token) params.append("authenticity_token", token);
    params.append("ai_prompt", prompt);

    try {
      const resp = await fetch(this.urlValue, {
        method: "POST",
        headers: {
          "Content-Type": "application/x-www-form-urlencoded",
          Accept: "application/json",
          "X-CSRF-Token": token || ""
        },
        body: params.toString()
      });
      const data = await resp.json();
      if (!resp.ok) {
        this.setStatus(data.error || "Could not generate draft.", true);
        return;
      }
      this.bodyTarget.value = data.report_content_preview;
      this.setStatus("Draft ready — edit, then save or create.", false);
    } catch (err) {
      console.error("[report-draft-from-prompt]", err);
      this.setStatus("Network error — try again.", true);
    }
  }

  setStatus(message, isError) {
    if (!this.hasStatusTarget) return;
    this.statusTarget.textContent = message;
    this.statusTarget.classList.toggle("text-error", isError);
    this.statusTarget.classList.toggle("text-on-surface-variant", !isError);
  }
}
