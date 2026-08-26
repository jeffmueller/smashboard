# frozen_string_literal: true

module HabitsHelper
  # A sequential ramp: one hue, light to dark, five steps.
  #
  # Written out as literal class names because Tailwind only ships classes it
  # can see in source — an interpolated `bg-accent/#{n}` compiles to nothing.
  # Level 0 is the neutral surface rather than the palest accent, so "nothing
  # happened" reads as absence instead of as a very small amount.
  #
  # Both ends work in either theme: `accent` and `raised` are semantic tokens
  # that flip with the palette, so the ramp keeps its direction against the
  # background in light and dark alike.
  ACTIVITY_LEVELS = {
    0 => 'bg-raised',
    1 => 'bg-accent/25',
    2 => 'bg-accent/45',
    3 => 'bg-accent/70',
    4 => 'bg-accent'
  }.freeze

  def activity_level_class(level)
    ACTIVITY_LEVELS.fetch(level.to_i, ACTIVITY_LEVELS[0])
  end

  # What the square means, spelled out — the grid must not rely on colour alone.
  def activity_cell_title(cell, habits)
    date = Date.parse(cell[:date]).strftime('%b %-d')
    names = habits.select { |habit| cell[:done_ids].include?(habit[:id]) }.pluck(:name)

    return "#{date} — nothing yet" if names.empty?

    "#{date} — #{names.to_sentence}"
  end
end
