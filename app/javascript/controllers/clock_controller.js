import { Controller } from "@hotwired/stimulus"

// Ticks the clock in the browser so the server never re-renders once a second.
// The zone comes from the user's profile, not the device, so a phone in another
// timezone still shows the board's time.
export default class extends Controller {
  static targets = ["time", "date"]
  static values = { timeZone: String }

  connect() {
    this.render()
    this.timer = setInterval(() => this.render(), 1000)
  }

  disconnect() {
    clearInterval(this.timer)
  }

  render() {
    const now = new Date()
    const zone = this.timeZoneValue || undefined

    this.timeTarget.textContent = now.toLocaleTimeString("en-US", {
      timeZone: zone,
      hour: "numeric",
      minute: "2-digit",
      second: "2-digit",
    })

    this.dateTarget.textContent = now.toLocaleDateString("en-US", {
      timeZone: zone,
      weekday: "long",
      month: "long",
      day: "numeric",
      year: "numeric",
    })
  }
}
