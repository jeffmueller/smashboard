import { Controller } from "@hotwired/stimulus"

// Filters the activity grid to one habit, or back to all of them.
//
// Done in the browser from data already rendered into the cells: the whole
// quarter is a few hundred small integers, so a round trip per chip would cost
// more than it saves, and it keeps working offline in the installed PWA.
export default class extends Controller {
  static targets = ["chip", "cell", "caption", "grid"]
  // ramp comes from HabitsHelper::ACTIVITY_LEVELS rather than being repeated
  // here: two copies of a colour scale drift, and the drift is invisible until
  // someone reads the wrong shade off the grid.
  static values = { levels: Number, total: Number, ramp: Array }

  connect() {
    this.habitId = ""
    this.paint()
  }

  filter(event) {
    this.habitId = event.currentTarget.dataset.habitId || ""
    this.paint()
  }

  paint() {
    this.chipTargets.forEach((chip) => {
      const active = (chip.dataset.habitId || "") === this.habitId
      chip.classList.toggle("bg-raised", active)
      chip.classList.toggle("text-ink", active)
      chip.setAttribute("aria-pressed", active ? "true" : "false")
    })

    let days = 0
    this.cellTargets.forEach((cell) => {
      const done = (cell.dataset.done || "").split(",").filter(Boolean)
      const hit = this.habitId ? done.includes(this.habitId) : done.length > 0
      if (hit) days += 1
      this.applyLevel(cell, this.levelFor(done))
    })

    this.captionTarget.textContent = this.habitId
      ? `${days} ${days === 1 ? "day" : "days"} in the last quarter`
      : `${days} ${days === 1 ? "day" : "days"} with something done`
  }

  // Filtered to one habit the square is binary — it happened or it didn't — so
  // it takes the top step rather than a quarter of one, which would render a
  // completed day as the palest possible shade.
  levelFor(done) {
    if (this.habitId) return done.includes(this.habitId) ? this.levelsValue : 0
    if (done.length === 0 || this.totalValue === 0) return 0

    return Math.min(Math.ceil((done.length / this.totalValue) * this.levelsValue), this.levelsValue)
  }

  applyLevel(cell, level) {
    this.rampValue.forEach((klass) => cell.classList.remove(...klass.split(" ")))
    cell.classList.add(...(this.rampValue[level] || this.rampValue[0]).split(" "))
  }
}
