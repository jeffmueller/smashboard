import { Controller } from "@hotwired/stimulus"
import { enablePushNotifications } from "push"

// Turns Web Push on for this browser and reports honestly why it can't, which
// matters because the failure modes are invisible: a denied permission looks
// identical to a broken button.
export default class extends Controller {
  static targets = ["status", "button"]
  static values = { enabled: Boolean }

  connect() {
    this.report()
  }

  report() {
    if (!("Notification" in window) || !("PushManager" in window)) {
      this.statusTarget.textContent = "This browser doesn't support push notifications."
      this.buttonTarget.disabled = true
      return
    }

    switch (Notification.permission) {
      case "granted":
        this.statusTarget.textContent = this.enabledValue
          ? "Notifications are on for this device."
          : "Permission granted — finish registering this device."
        this.buttonTarget.textContent = this.enabledValue ? "Re-register" : "Finish setup"
        break
      case "denied":
        this.statusTarget.textContent =
          "Blocked in your browser settings — allow notifications for this site, then reload."
        this.buttonTarget.disabled = true
        break
      default:
        this.statusTarget.textContent = "Not turned on for this device yet."
    }
  }

  async enable() {
    this.buttonTarget.disabled = true
    this.statusTarget.textContent = "Asking your browser…"

    try {
      const ok = await enablePushNotifications()
      this.statusTarget.textContent = ok
        ? "Notifications are on for this device."
        : "Couldn't turn notifications on — permission was refused."
      this.enabledValue = ok
    } catch (error) {
      this.statusTarget.textContent = `Couldn't turn notifications on: ${error.message}`
    } finally {
      this.buttonTarget.disabled = Notification.permission === "denied"
    }
  }
}
