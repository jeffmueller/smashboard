# frozen_string_literal: true

# One habit, done on one day. Its existence is the whole record — there is no
# "missed" row, because a miss is simply the absence of one.
class HabitCompletion < ApplicationRecord
  belongs_to :habit

  validates :completed_on, presence: true
  validates :completed_on, uniqueness: { scope: :habit_id }

  scope :between, ->(from, to) { where(completed_on: from..to) }
end
