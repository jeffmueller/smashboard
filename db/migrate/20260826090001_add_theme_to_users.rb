# frozen_string_literal: true

# Null means "follow the operating system", which is what the generated
# stylesheet's prefers-color-scheme block handles. A slug pins an explicit
# choice and wins over the OS.
class AddThemeToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :theme, :string
  end
end
