# frozen_string_literal: true

# Hand-orderable records: a `position` column the user rearranges by dragging.
#
# `apply_order` is written against the relation it's called on, so the caller's
# scoping is what decides ownership — `current_user.bookmarks.apply_order(ids)`
# cannot touch another user's rows however the ids were forged.
module Positioned
  extend ActiveSupport::Concern

  included do
    scope :ordered, -> { order(:position, :id) }
  end

  class_methods do
    # Takes the full ordered list of ids after a drag-and-drop and rewrites
    # positions in one transaction, ignoring any id outside the relation.
    def apply_order(ids)
      wanted = Array(ids).map(&:to_i)
      owned = where(id: wanted).pluck(:id).to_set
      ordered = wanted.select { |id| owned.include?(id) }
      return false if ordered.empty?

      transaction do
        ordered.each_with_index do |id, index|
          # Bulk position rewrite: nothing here needs validations or callbacks,
          # and instantiating every record to move it would be wasteful.
          where(id: id).update_all(position: index, updated_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
        end
      end

      true
    end

    # The position a newly added record should take: the end of the list.
    def next_position
      (maximum(:position) || -1) + 1
    end
  end
end
