# frozen_string_literal: true

module Integrations
  # Unread counts and previews from the Gmail API.
  #
  # The API rather than IMAP-with-XOAUTH2 on purpose: IMAP needs the
  # `https://mail.google.com/` scope, which also grants send and delete, while
  # this needs only `gmail.readonly`. It also hands over a ready-made `snippet`
  # per message, so none of the MIME decoding the IMAP client does is needed.
  class Gmail < Base
    include GoogleToken

    # Trailing slash, relative paths: Faraday treats a leading-slash path as
    # absolute and would drop /gmail/v1/users/me.
    BASE_URL = 'https://gmail.googleapis.com/gmail/v1/users/me/'
    DEFAULT_QUERY = 'is:unread in:inbox'
    HEADERS = %w[From Subject Date].freeze
    SNIPPET_LENGTH = 160

    def unread(limit: 5)
      listing = request { get('messages', q: query, maxResults: limit.to_i.clamp(1, 25)) }
      ids = Array(listing['messages']).pluck('id')

      { unread_count: listing['resultSizeEstimate'].to_i, messages: ids.map { |id| message(id) }.compact }
    end

    private

    def message(id)
      body = request { get("messages/#{id}", format: 'metadata', metadataHeaders: HEADERS) }
      headers = header_map(body)

      {
        uid: id,
        message_id: id,
        from: sender(headers['from']),
        subject: decode(headers['subject']).presence || '(no subject)',
        received_at: received_at(body, headers),
        preview: snippet(body['snippet']),
        account: connection.label
      }
    rescue Base::Error => e
      # One unreadable message shouldn't cost the whole mailbox.
      Rails.logger.info("[gmail] could not read message #{id}: #{e.message}")
      nil
    end

    def header_map(body)
      Array(body.dig('payload', 'headers'))
        .to_h { |header| [header['name'].to_s.downcase, header['value']] }
    end

    # "Dana Lee <dana@example.com>" reads better as just the name.
    def sender(value)
      return 'Unknown sender' if value.blank?

      address = Mail::Address.new(value.to_s)
      decode(address.display_name).presence || address.address.presence || value.to_s
    rescue StandardError
      decode(value).presence || value.to_s
    end

    # Gmail snippets arrive HTML-escaped.
    def snippet(value)
      return nil if value.blank?

      CGI.unescapeHTML(value.to_s).squish.truncate(SNIPPET_LENGTH).presence
    end

    def received_at(body, headers)
      internal = body['internalDate'].presence
      return Time.zone.at(internal.to_i / 1000).utc if internal

      Time.parse(headers['date'].to_s).utc
    rescue StandardError
      nil
    end

    def decode(value)
      return nil if value.blank?

      Mail::Encodings.value_decode(value.to_s)
    rescue StandardError
      value.to_s
    end

    def query
      setting('query').presence || DEFAULT_QUERY
    end

    def get(path, params)
      http(BASE_URL).get(path, params) do |request|
        request.headers['Authorization'] = "Bearer #{access_token}"
      end
    end
  end
end
