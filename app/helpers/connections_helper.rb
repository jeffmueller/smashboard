# frozen_string_literal: true

module ConnectionsHelper
  # Providers whose credential comes from an authorization flow skip the form
  # entirely — there would be nothing to type into it.
  def connect_path(provider)
    return new_connection_path(provider: provider.key) unless provider.oauth?

    public_send("oauth_#{provider.oauth}_path", provider: provider.key)
  end

  def reconnect_path(connection, provider)
    public_send("oauth_#{provider.oauth}_path", provider: connection.provider, connection_id: connection.id)
  end
end
