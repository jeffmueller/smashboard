import { Controller } from "@hotwired/stimulus"

// An emoji picker over the bundled Unicode list.
//
// The data is a 66KB module, so it's pulled in with a dynamic import the first
// time a picker is opened rather than on every page that renders one.
//
// The panel is positioned in viewport coordinates for the same reason the panel
// menu is: it can sit inside the row's own edit popover, and any clipped
// ancestor beats a z-index.
export default class extends Controller {
  static targets = ["input", "display", "button", "panel", "search", "tabs", "grid"]

  connect() {
    this.groups = null
    this.activeGroup = 0
    this.closeOnOutside = (event) => {
      if (!this.element.contains(event.target) && !this.panelTarget.contains(event.target)) this.close()
    }
    this.closeOnEscape = (event) => { if (event.key === "Escape") this.close() }
  }

  disconnect() {
    this.close()
  }

  async toggle(event) {
    event.preventDefault()
    if (this.panelTarget.hidden) await this.open()
    else this.close()
  }

  async open() {
    if (!this.groups) {
      const { EMOJI_GROUPS } = await import("emoji_data")
      this.groups = EMOJI_GROUPS
      this.renderTabs()
    }

    this.searchTarget.value = ""
    this.panelTarget.hidden = false
    this.position()
    this.renderGrid()
    this.searchTarget.focus()

    document.addEventListener("click", this.closeOnOutside)
    document.addEventListener("keydown", this.closeOnEscape)
  }

  close() {
    this.panelTarget.hidden = true
    document.removeEventListener("click", this.closeOnOutside)
    document.removeEventListener("keydown", this.closeOnEscape)
  }

  // Anchored under the button, flipped up or nudged left when it would other-
  // wise run off the bottom or the right of the window.
  position() {
    const anchor = this.buttonTarget.getBoundingClientRect()
    const panel = this.panelTarget.getBoundingClientRect()
    const margin = 8

    let top = anchor.bottom + 6
    if (top + panel.height > window.innerHeight - margin) {
      top = Math.max(margin, anchor.top - panel.height - 6)
    }

    let left = anchor.left
    if (left + panel.width > window.innerWidth - margin) {
      left = Math.max(margin, window.innerWidth - panel.width - margin)
    }

    this.panelTarget.style.top = `${top}px`
    this.panelTarget.style.left = `${left}px`
  }

  renderTabs() {
    this.tabsTarget.replaceChildren(...this.groups.map((group, index) => {
      const tab = document.createElement("button")
      tab.type = "button"
      tab.textContent = GROUP_ICONS[group.name] || "•"
      tab.title = group.name
      tab.className = "rounded px-1.5 py-1 text-base leading-none hover:bg-raised"
      tab.addEventListener("click", () => {
        this.activeGroup = index
        this.searchTarget.value = ""
        this.renderGrid()
      })
      return tab
    }))
  }

  search() {
    this.renderGrid()
  }

  renderGrid() {
    const query = this.searchTarget.value.trim().toLowerCase()

    // Searching scans every group; browsing shows one. Results are capped so a
    // one-letter query doesn't paint two thousand buttons.
    const matches = query
      ? this.groups.flatMap((group) => group.emoji).filter(([, name]) => name.includes(query)).slice(0, 180)
      : this.groups[this.activeGroup].emoji

    if (matches.length === 0) {
      const empty = document.createElement("p")
      empty.className = "col-span-8 px-1 py-3 text-center text-xs text-ink-faint"
      empty.textContent = "No emoji match that."
      this.gridTarget.replaceChildren(empty)
      return
    }

    this.gridTarget.replaceChildren(...matches.map(([char, name]) => {
      const button = document.createElement("button")
      button.type = "button"
      button.textContent = char
      button.title = name
      button.className = "rounded p-1 text-xl leading-none hover:bg-raised"
      button.addEventListener("click", () => this.choose(char))
      return button
    }))
    this.gridTarget.scrollTop = 0
  }

  choose(char) {
    this.inputTarget.value = char
    this.displayTarget.textContent = char
    this.displayTarget.classList.remove("opacity-40")
    this.close()
    this.inputTarget.dispatchEvent(new Event("change", { bubbles: true }))
  }

  clear(event) {
    event.preventDefault()
    this.inputTarget.value = ""
    this.displayTarget.textContent = PLACEHOLDER
    this.displayTarget.classList.add("opacity-40")
    this.close()
    this.inputTarget.dispatchEvent(new Event("change", { bubbles: true }))
  }
}

const PLACEHOLDER = "🔖"

const GROUP_ICONS = {
  "Smileys & Emotion": "😀",
  "People & Body": "👋",
  "Animals & Nature": "🐻",
  "Food & Drink": "🍎",
  "Travel & Places": "✈️",
  "Activities": "⚽",
  "Objects": "💡",
  "Symbols": "🔣",
  "Flags": "🏳️",
}
