# frozen_string_literal: true

class SplitUserName < ActiveRecord::Migration[8.1]
  def up
    change_table :users, bulk: true do |t|
      t.string :first_name
      t.string :last_name
    end

    # Best-effort split of whatever single name was there: everything before the
    # first space is the given name, the remainder the family name.
    execute <<~SQL.squish
      UPDATE users
      SET first_name = NULLIF(split_part(name, ' ', 1), ''),
          last_name  = NULLIF(NULLIF(substring(name from position(' ' in name) + 1), name), '')
      WHERE name IS NOT NULL AND name <> ''
    SQL

    remove_column :users, :name
  end

  def down
    add_column :users, :name, :string
    execute "UPDATE users SET name = TRIM(CONCAT(COALESCE(first_name, ''), ' ', COALESCE(last_name, '')))"

    change_table :users, bulk: true do |t|
      t.remove :first_name
      t.remove :last_name
    end
  end
end
