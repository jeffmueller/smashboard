import { Controller } from "@hotwired/stimulus"

// The per-panel width and hide menu.
//
// The menu is positioned in viewport coordinates rather than with `absolute`,
// because the panel clips its own content to keep its rounded corners — and a
// clipped ancestor beats any z-index, so an absolutely-positioned menu is cut
// off on a short panel. Measuring also lets it flip upward near the bottom of
// the window instead of opening off-screen.
export default class extends Controller {
  static targets = ["menu", "button"]

  // Space between the button and the menu, and the minimum gap kept from any
  // window edge.
  static GAP = 4
  static MARGIN = 8

  connect() {
    this.onOutside = (event) => {
      if (!this.element.contains(event.target)) this.close()
    }
    this.onEscape = (event) => {
      if (event.key === "Escape") this.close()
    }
    // A fixed menu would sit still while the board scrolled underneath it.
    this.onReflow = () => this.close()

    document.addEventListener("click", this.onOutside)
    document.addEventListener("keydown", this.onEscape)
    window.addEventListener("scroll", this.onReflow, true)
    window.addEventListener("resize", this.onReflow)
  }

  disconnect() {
    document.removeEventListener("click", this.onOutside)
    document.removeEventListener("keydown", this.onEscape)
    window.removeEventListener("scroll", this.onReflow, true)
    window.removeEventListener("resize", this.onReflow)
  }

  toggle(event) {
    // The panel header is a drag handle; opening a menu is not a drag.
    event.stopPropagation()
    this.menuTarget.hidden ? this.open() : this.close()
  }

  open() {
    // Unhide first so the menu has measurable dimensions.
    this.menuTarget.hidden = false
    this.position()
  }

  close() {
    if (this.hasMenuTarget) this.menuTarget.hidden = true
  }

  position() {
    const { GAP, MARGIN } = this.constructor
    const button = this.buttonTarget.getBoundingClientRect()
    const menu = this.menuTarget.getBoundingClientRect()

    const fitsBelow = window.innerHeight - button.bottom >= menu.height + GAP + MARGIN
    const top = fitsBelow ? button.bottom + GAP : button.top - menu.height - GAP
    const left = button.right - menu.width

    this.menuTarget.style.top = `${this.clamp(top, window.innerHeight - menu.height)}px`
    this.menuTarget.style.left = `${this.clamp(left, window.innerWidth - menu.width)}px`
  }

  clamp(value, max) {
    const { MARGIN } = this.constructor

    return Math.max(MARGIN, Math.min(value, max - MARGIN))
  }
}
