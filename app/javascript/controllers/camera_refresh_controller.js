import { Controller } from "@hotwired/stimulus"

// Pulls a fresh frame for each camera on an interval. The panel itself doesn't
// re-render — only the image sources change — so this stays cheap no matter how
// many cameras are on screen.
export default class extends Controller {
  static targets = ["image", "status"]
  static values = { interval: Number }

  connect() {
    this.failures = new Set()
    this.refresh()
    this.timer = setInterval(() => this.refresh(), this.seconds() * 1000)

    // Coming back to the tab should show something current immediately.
    this.onVisibility = () => { if (!document.hidden) this.refresh() }
    document.addEventListener("visibilitychange", this.onVisibility)
  }

  disconnect() {
    clearInterval(this.timer)
    document.removeEventListener("visibilitychange", this.onVisibility)
  }

  seconds() {
    return this.intervalValue > 0 ? this.intervalValue : 30
  }

  refresh() {
    // A backgrounded tab shouldn't keep waking the Raspberry Pi.
    if (document.hidden) return

    this.imageTargets.forEach((image) => {
      const url = new URL(image.dataset.src, window.location.origin)
      url.searchParams.set("t", Date.now())
      image.src = url.toString()
    })
  }

  loaded(event) {
    event.target.classList.remove("opacity-30")
    this.failures.delete(event.target.dataset.src)
    this.report()
  }

  failed(event) {
    // Keep the last good frame on screen, dimmed, rather than flashing a broken
    // image icon every time one camera hiccups.
    event.target.classList.add("opacity-30")
    this.failures.add(event.target.dataset.src)
    this.report()
  }

  report() {
    if (!this.hasStatusTarget) return

    const count = this.failures.size
    this.statusTarget.textContent = count === 0
      ? `Refreshing every ${this.seconds()}s`
      : `${count} camera${count === 1 ? "" : "s"} not responding`
  }
}
