# frozen_string_literal: true

# Records that one specific occurrence of a countdown was waved off. Scoped to
# the occurrence rather than the countdown so the next iteration is unaffected.
class CountdownDismissal < ApplicationRecord
  belongs_to :countdown

  validates :occurrence_at, presence: true,
                            uniqueness: { scope: :countdown_id }
end
