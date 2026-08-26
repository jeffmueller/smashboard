# frozen_string_literal: true

class TodoProject < ApplicationRecord
  COLORS = %w[slate sky emerald amber rose violet].freeze

  belongs_to :user
  has_many :todos, dependent: :nullify

  validates :name, presence: true, length: { maximum: 120 }
  validates :color, inclusion: { in: COLORS }

  scope :active, -> { where(archived_at: nil) }
  scope :ordered, -> { order(:position, :id) }

  def archived?
    archived_at.present?
  end
end
