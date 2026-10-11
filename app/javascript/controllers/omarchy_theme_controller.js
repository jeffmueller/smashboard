import { Controller } from "@hotwired/stimulus"
import { setFollowing, state } from "omarchy_theme"

// The appearance page's "Follow my Omarchy theme" switch. The setting itself is
// per device and lives in omarchy_theme.js; this only drives it and reports
// what the bridge is doing, since every way it fails is otherwise invisible.
export default class extends Controller {
  static targets = ["toggle", "status", "picker"]

  connect() {
    this.update = (event) => this.render(event.detail)
    document.addEventListener("omarchy-theme:status", this.update)
    this.render(state())
  }

  disconnect() {
    document.removeEventListener("omarchy-theme:status", this.update)
  }

  toggle() {
    setFollowing(this.toggleTarget.checked)
    this.render(state())
  }

  render({ following, status, theme }) {
    this.toggleTarget.checked = following
    this.statusTarget.textContent = this.describe(following, status, theme)

    // The picker still works while following — it's the account's theme, for
    // every other device — but on this one the desktop's palette wins.
    if (this.hasPickerTarget) this.pickerTarget.classList.toggle("opacity-50", following)
  }

  describe(following, status, theme) {
    if (!following) return "Off on this device."

    switch (status) {
      case "live":
        return `Following ${theme ? `“${theme}”` : "your desktop"}. Change it with omarchy theme set.`
      case "no-palette":
        return "The bridge is running but has no palette yet. Apply a theme with omarchy theme set."
      case "unreachable":
        return "Can't reach the theme bridge on this device; retrying. Check systemctl --user status notey-omarchy-theme, and that this site may access apps on this device."
      default:
        return "Connecting to the theme bridge… if your browser asks to let this site access apps on this device, allow it."
    }
  }
}
