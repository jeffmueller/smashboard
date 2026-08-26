# frozen_string_literal: true

class CreateBookmarks < ActiveRecord::Migration[8.1]
  def change
    create_table :bookmarks do |t|
      t.references :user, null: false, foreign_key: true
      t.string :title, null: false
      t.string :url, null: false
      # An optional emoji. Deliberately not a fetched favicon: that would mean
      # asking a third party for an icon per bookmark on every render, handing
      # them the list of sites this user cares about.
      t.string :icon
      t.integer :position, null: false, default: 0

      t.timestamps
    end

    add_index :bookmarks, %i[user_id position]
  end
end
