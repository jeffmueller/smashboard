import { Controller } from "@hotwired/stimulus"

// Keeps the "in 12m" / "started 5m ago" label live without re-rendering the
// panel. The panel itself only refreshes every few minutes, so without this the
// relative labels would visibly drift.
export default class extends Controller {
  static targets = ["event", "relative"]

  connect() {
    this.render()
    this.timer = setInterval(() => this.render(), 30000)
  }

  disconnect() {
    clearInterval(this.timer)
  }

  render() {
    const now = new Date()

    this.eventTargets.forEach((event, index) => {
      const label = this.relativeTargets[index]
      if (!label) return

      // An all-day event's boundaries are UTC midnights, so a countdown to its
      // "end" would be both wrong for the viewer's day and useless to them.
      if (event.dataset.allDay === "true") {
        label.textContent = ""
        return
      }

      const starts = new Date(event.dataset.startsAt)
      const ends = new Date(event.dataset.endsAt)

      if (now >= ends) {
        label.textContent = ""
      } else if (now >= starts) {
        label.textContent = `ends in ${this.humanize(ends - now)}`
      } else {
        label.textContent = `in ${this.humanize(starts - now)}`
      }
    })
  }

  humanize(milliseconds) {
    const minutes = Math.round(milliseconds / 60000)
    if (minutes < 1) return "under a minute"
    if (minutes < 60) return `${minutes}m`

    const hours = Math.floor(minutes / 60)
    const remainder = minutes % 60
    return remainder === 0 ? `${hours}h` : `${hours}h ${remainder}m`
  }
}
