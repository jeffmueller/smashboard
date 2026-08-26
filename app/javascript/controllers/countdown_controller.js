import { Controller } from "@hotwired/stimulus"

// Counts down to an absolute instant handed over as ISO 8601. Because the
// target is absolute, clock skew between server and browser only affects the
// displayed remainder, never which occurrence is being counted to.
export default class extends Controller {
  static targets = ["remaining"]
  static values = { targetAt: String }

  connect() {
    this.target = new Date(this.targetAtValue)
    this.render()
    this.timer = setInterval(() => this.render(), 1000)
  }

  disconnect() {
    clearInterval(this.timer)
  }

  render() {
    const seconds = Math.round((this.target - new Date()) / 1000)

    if (seconds <= 0) {
      this.remainingTarget.textContent = "now"
      clearInterval(this.timer)
      return
    }

    this.remainingTarget.textContent = this.format(seconds)
  }

  format(totalSeconds) {
    const days = Math.floor(totalSeconds / 86400)
    const hours = Math.floor((totalSeconds % 86400) / 3600)
    const minutes = Math.floor((totalSeconds % 3600) / 60)
    const seconds = totalSeconds % 60

    // Past a day the seconds are noise; under an hour they're the whole point.
    if (days > 0) return `${days}d ${hours}h`
    if (hours > 0) return `${hours}h ${String(minutes).padStart(2, "0")}m`
    return `${minutes}:${String(seconds).padStart(2, "0")}`
  }
}
