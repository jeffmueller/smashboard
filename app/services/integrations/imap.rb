# frozen_string_literal: true

require 'net/imap'

module Integrations
  # Unread counts and message previews over IMAP, for Fastmail, Gmail and
  # anything else that speaks the protocol. Authentication is an app password;
  # both providers issue those and neither needs OAuth for IMAP.
  #
  # Two details keep this panel from destroying the thing it reports on:
  #
  #   * EXAMINE, not SELECT — the mailbox is opened read-only, so nothing here
  #     can change message state even by accident.
  #   * BODY.PEEK[...], not BODY[...] — a plain BODY fetch sets \Seen on every
  #     message it touches. Rendering an unread-mail panel with BODY would mark
  #     the mail read and empty the panel out from under the user.
  class Imap < Base
    DEFAULT_PORT = 993
    DEFAULT_MAILBOX = 'INBOX'

    # Enough of the body for a preview without pulling whole attachments.
    PREVIEW_BYTES = 4096
    SNIPPET_LENGTH = 160

    # So a connection usually needs nothing but an address and an app password.
    HOSTS_BY_DOMAIN = {
      'gmail.com' => 'imap.gmail.com',
      'googlemail.com' => 'imap.gmail.com',
      'fastmail.com' => 'imap.fastmail.com',
      'fastmail.fm' => 'imap.fastmail.com',
      'messagingengine.com' => 'imap.fastmail.com',
      'icloud.com' => 'imap.mail.me.com',
      'me.com' => 'imap.mail.me.com',
      'outlook.com' => 'outlook.office365.com',
      'hotmail.com' => 'outlook.office365.com',
      'yahoo.com' => 'imap.mail.yahoo.com'
    }.freeze

    def unread(limit: 5)
      connect do |imap|
        count = unread_count(imap)

        { unread_count: count, messages: count.zero? ? [] : recent_unread(imap, limit) }
      end
    end

    private

    # STATUS answers the count without opening the mailbox at all, which is both
    # cheaper and incapable of touching message state.
    def unread_count(imap)
      imap.status(mailbox, ['UNSEEN'])['UNSEEN'].to_i
    rescue Net::IMAP::NoResponseError => e
      raise Unavailable, "mailbox #{mailbox} is unavailable: #{response_text(e)}"
    end

    def recent_unread(imap, limit)
      imap.examine(mailbox)
      uids = Array(imap.uid_search(['UNSEEN'])).last(limit).reverse
      return [] if uids.empty?

      imap.uid_fetch(uids, [
                       'UID',
                       'ENVELOPE',
                       'INTERNALDATE',
                       'BODY.PEEK[HEADER.FIELDS (CONTENT-TYPE CONTENT-TRANSFER-ENCODING)]',
                       "BODY.PEEK[TEXT]<0.#{PREVIEW_BYTES}>"
                     ]).map { |data| normalize(data) }
    end

    def normalize(data)
      envelope = data.attr['ENVELOPE']

      {
        uid: data.attr['UID'],
        message_id: envelope&.message_id,
        from: sender_of(envelope),
        subject: decode(envelope&.subject).presence || '(no subject)',
        received_at: (data.attr['INTERNALDATE'] || envelope&.date)&.then { |value| to_time(value) },
        preview: snippet(body_part(data, 'BODY[HEADER'), body_part(data, 'BODY[TEXT]')),
        account: connection.label
      }
    end

    # Servers echo the fetch item back without the PEEK, and append the octet
    # offset for a partial fetch, so the key is matched by prefix rather than
    # reconstructed.
    def body_part(data, prefix)
      key = data.attr.keys.find { |candidate| candidate.to_s.start_with?(prefix) }
      key && data.attr[key]
    end

    def sender_of(envelope)
      address = Array(envelope&.from).first
      return 'Unknown sender' if address.nil?

      decode(address.name).presence || [address.mailbox, address.host].compact.join('@')
    end

    # Headers and body are refetched separately, then stitched back together so
    # the mail gem can do the transfer-encoding and charset work.
    def snippet(headers, text)
      return nil if text.blank?

      mail = Mail.read_from_string("#{headers}\r\n#{text}")
      part = mail.multipart? ? (mail.text_part || mail.html_part) : mail
      return fallback_snippet(text) if part.nil?

      content = part.decoded
      content = strip_html(content) if part.mime_type == 'text/html'
      clean(content)
    rescue StandardError
      # A body truncated mid-MIME can defeat the parser; the raw text is still
      # worth something as a preview.
      fallback_snippet(text)
    end

    def fallback_snippet(text)
      clean(strip_html(text.to_s))
    end

    def strip_html(content)
      Nokogiri::HTML(content).text
    rescue StandardError
      content.gsub(/<[^>]+>/, ' ')
    end

    def clean(content)
      content.to_s.squish.truncate(SNIPPET_LENGTH).presence
    end

    def decode(value)
      return nil if value.blank?

      Mail::Encodings.value_decode(value.to_s)
    rescue StandardError
      value.to_s
    end

    def to_time(value)
      value.is_a?(Time) ? value.utc : Time.parse(value.to_s).utc
    rescue StandardError
      nil
    end

    # --- Connection ---------------------------------------------------------

    def connect
      imap = open_connection
      sign_in(imap)
      yield imap
    ensure
      close(imap)
    end

    def open_connection
      Net::IMAP.new(host, port: port, ssl: ssl?, open_timeout: OPEN_TIMEOUT)
    rescue Net::OpenTimeout, SocketError, Errno::ECONNREFUSED, Errno::EHOSTUNREACH, OpenSSL::SSL::SSLError => e
      raise Unavailable, "could not reach #{host}:#{port} — #{e.class.name.demodulize}"
    end

    def sign_in(imap)
      imap.login(username, password)
    rescue Net::IMAP::NoResponseError, Net::IMAP::BadResponseError => e
      # The server's own text is the actionable part: Gmail says outright when
      # it wants an app password rather than an account password.
      raise AuthenticationError, "#{host} rejected the credentials: #{response_text(e)}"
    end

    def close(imap)
      return if imap.nil? || imap.disconnected?

      begin
        imap.logout
      rescue StandardError
        nil
      end
      imap.disconnect unless imap.disconnected?
    rescue StandardError
      nil
    end

    def response_text(error)
      error.response&.data&.text.to_s.strip.presence || error.message
    end

    def host
      configured = setting('host').presence
      return configured if configured

      domain = username.to_s.split('@').last.to_s.downcase
      HOSTS_BY_DOMAIN[domain].presence ||
        raise(Unavailable, "no IMAP host configured, and #{domain.presence || 'this address'} isn't a known provider")
    end

    def port
      setting('port').presence&.to_i || DEFAULT_PORT
    end

    # Off only makes sense for a local or trusted-network server; the form says so.
    def ssl?
      value = setting('ssl')
      value.nil? || value.to_s.strip.empty? || ActiveModel::Type::Boolean.new.cast(value)
    end

    def mailbox
      setting('mailbox').presence || DEFAULT_MAILBOX
    end

    def username
      credentials['username']
    end

    def password
      credentials['password']
    end
  end
end
