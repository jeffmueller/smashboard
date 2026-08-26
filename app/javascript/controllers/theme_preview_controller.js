import { Controller } from "@hotwired/stimulus"

// Applies a theme to <html> the moment it's clicked, so the whole page — not a
// swatch — is the preview. Saving persists it; navigating away without saving
// simply drops it, since the server re-renders from the stored preference.
export default class extends Controller {
  static targets = ["status"]

  connect() {
    this.original = document.documentElement.dataset.theme || ""
  }

  preview(event) {
    const slug = event.params.slug || ""
    this.apply(slug)

    if (!this.hasStatusTarget) return
    this.statusTarget.textContent = slug === this.original
      ? "Previewing as you click; save to keep it."
      : "Previewing — save to keep it."
  }

  apply(slug) {
    if (slug) {
      document.documentElement.dataset.theme = slug
    } else {
      // Removing the attribute hands control back to prefers-color-scheme.
      delete document.documentElement.dataset.theme
    }
  }
}
