# frozen_string_literal: true

# When an authorization flow last granted this connection its credential. Only
# meaningful for OAuth providers; nil everywhere else.
class AddAuthorizedAtToConnections < ActiveRecord::Migration[8.1]
  def change
    add_column :connections, :authorized_at, :datetime
  end
end
