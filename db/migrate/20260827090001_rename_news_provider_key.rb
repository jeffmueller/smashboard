# frozen_string_literal: true

# Renames the breaking-news provider key on existing connections.
#
# `connections.provider` is a persisted string validated against
# ConnectionProvider::CATALOG, so a row still holding the previous key stops
# matching NewsPanel.required_providers and can no longer be saved at all once
# the catalogue entry is renamed.
#
# The previous key belongs to whichever instance is being upgraded rather than
# to this repository, so it comes from the environment: set
# LEGACY_NEWS_PROVIDER_KEY for the one deploy that carries this migration, then
# drop it again. Unset, this is a no-op — which is what a fresh install wants,
# since no such row can exist there.
#
# Raw SQL on purpose. Connection encrypts :credentials, so loading and saving
# the model would decrypt and re-encrypt a column this change never touches,
# which needs the encryption keys present and risks the blob if they are
# mid-rotation. It would also bind a frozen migration to Connection::PROVIDERS,
# a constant that keeps moving. `provider` is a plain string and `settings` a
# plain jsonb, so neither statement here goes near the ciphertext.
class RenameNewsProviderKey < ActiveRecord::Migration[8.1]
  NEW_KEY = 'news_feed'

  def up
    return if legacy_key.blank?

    execute sanitize(['UPDATE connections SET provider = ? WHERE provider = ?', NEW_KEY, legacy_key])

    # Values the old client took from constants or differently-named environment
    # variables now live on the connection, so the panel keeps working across
    # the restart without anyone having to open the settings form.
    backfill('base_url', ENV.fetch('NEWS_FEED_BASE_URL', nil))
    backfill('cookie_name', ENV.fetch('NEWS_FEED_AUTH_COOKIE', nil))
  end

  # The settings backfill is deliberately not undone: the older client ignores
  # keys it does not read, so leaving them costs nothing, while stripping them
  # could discard a value edited by hand since.
  def down
    return if legacy_key.blank?

    execute sanitize(['UPDATE connections SET provider = ? WHERE provider = ?', legacy_key, NEW_KEY])
  end

  private

  def legacy_key
    @legacy_key ||= ENV.fetch('LEGACY_NEWS_PROVIDER_KEY', nil).to_s.strip
  end

  # Fills a gap only; anything already stored on the connection wins.
  def backfill(key, value)
    return if value.blank?

    execute sanitize([<<~SQL.squish, key, value, NEW_KEY, key])
      UPDATE connections
         SET settings = settings || jsonb_build_object(?, ?)
       WHERE provider = ?
         AND COALESCE(settings ->> ?, '') = ''
    SQL
  end

  def sanitize(statement)
    ActiveRecord::Base.sanitize_sql_array(statement)
  end
end
