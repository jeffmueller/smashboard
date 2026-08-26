import { Controller } from "@hotwired/stimulus"

// The header's navigation, collapsed behind one button.
//
// Absolutely positioned, unlike the panel menu: the header doesn't clip its
// own content, so there's no clipped ancestor to escape and the menu can just
// travel with the sticky header.
export default class extends Controller {
  static targets = ["button", "menu"]

  connect() {
    // pointerdown rather than click: iOS only synthesises a click for elements
    // it considers interactive, so tapping a plain area of the page to dismiss
    // the menu would otherwise do nothing.
    this.closeOnOutside = (event) => {
      if (!this.element.contains(event.target)) this.close()
    }
    this.closeOnEscape = (event) => {
      if (event.key !== "Escape" || !this.open) return
      this.close()
      this.buttonTarget.focus()
    }
    // Turbo caches the page as it was when you left it. Without this, going
    // back paints a preview with the menu hanging open.
    this.closeOnCache = () => this.close()
    document.addEventListener("turbo:before-cache", this.closeOnCache)
  }

  disconnect() {
    this.stopListening()
    document.removeEventListener("turbo:before-cache", this.closeOnCache)
  }

  get open() {
    return !this.menuTarget.hidden
  }

  toggle(event) {
    event.preventDefault()
    // A click from Enter or Space reports no pointer behind it, which is how
    // keyboard activation is told apart from a tap or a mouse press.
    if (this.open) this.close()
    else this.show(event.detail === 0)
  }

  show(keyboard = false) {
    this.menuTarget.hidden = false
    this.buttonTarget.setAttribute("aria-expanded", "true")
    document.addEventListener("pointerdown", this.closeOnOutside)
    document.addEventListener("keydown", this.closeOnEscape)

    // Only when opened from the keyboard. Moving focus on a touch open puts a
    // focused element inside a menu the next tap is about to leave, and the
    // focus events that follow are exactly what used to swallow that tap.
    if (keyboard) this.menuTarget.querySelector("a, button")?.focus()
  }

  close() {
    if (!this.open) return

    this.menuTarget.hidden = true
    this.buttonTarget.setAttribute("aria-expanded", "false")
    this.stopListening()
  }

  // Tabbing past the last item should close the menu, the same as clicking away.
  //
  // Only acts when focus demonstrably landed somewhere else. iOS does not focus
  // a link when you tap it, so the focused element emits focusout with a null
  // relatedTarget *before* the click is delivered — reading that as "focus
  // left" hid the menu mid-tap and the link never received the click, which is
  // why every item looked dead on a phone while working on a desktop.
  closeIfLeft(event) {
    const movedTo = event.relatedTarget

    if (movedTo && !this.element.contains(movedTo)) this.close()
  }

  stopListening() {
    document.removeEventListener("pointerdown", this.closeOnOutside)
    document.removeEventListener("keydown", this.closeOnEscape)
  }
}
