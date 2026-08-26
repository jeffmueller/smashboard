# frozen_string_literal: true

module ApiHelpers
  # Returns the headers a client needs to talk to /api/v1, creating a token for
  # the user on the way.
  def api_headers_for(user)
    token = user.api_tokens.create!(name: 'spec')
    { 'Authorization' => "Bearer #{token.plaintext_token}", 'Accept' => 'application/json' }
  end
end

RSpec.configure do |config|
  config.include ApiHelpers, type: :request
end
