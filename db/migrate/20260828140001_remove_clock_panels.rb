# frozen_string_literal: true

# The clock moved out of the board and into the top bar, where it is part of the
# chrome rather than a tile someone has to keep.
#
# `panels.kind` is a persisted string validated against Panel::KINDS, so a row
# left holding 'clock' stops matching any panel class: ApplicationPanel.for
# raises UnknownPanel and the whole board fails to render, not just that tile.
# The rows have to go with the class.
class RemoveClockPanels < ActiveRecord::Migration[8.1]
  def up
    # Raw SQL: nothing here needs callbacks, and Panel's own validation is
    # derived from a constant that will keep moving after this migration is
    # frozen in history.
    execute "DELETE FROM panels WHERE kind = 'clock'"
  end

  # Deliberately not reversible. Re-inserting rows would have to invent the
  # position each one held on its owner's board, and a board that is simply
  # missing the tile is what rolling back should give you — Dashboards::InstallDefaults
  # no longer installs it either.
  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
