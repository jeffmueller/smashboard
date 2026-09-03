# frozen_string_literal: true

require 'net/http'

module Integrations
  # CalDAV client for Fastmail (and any other RFC 4791 server).
  #
  # Net::HTTP rather than Faraday: CalDAV needs PROPFIND and REPORT, and
  # Faraday 2 rejects any verb outside its fixed list before the adapter is
  # ever reached.
  #
  # The happy path asks the *server* to expand recurring events into individual
  # occurrences, which is the only way to get RECURRENCE-ID overrides (a single
  # moved instance of a weekly meeting) right. Servers that reject that form
  # fall back to client-side expansion via Meetings::RecurrenceExpander.
  class Caldav < Base
    NAMESPACES = { 'd' => 'DAV:', 'c' => 'urn:ietf:params:xml:ns:caldav' }.freeze
    MAX_REDIRECTS = 3
    DISCOVERY_TTL = 12.hours

    PRINCIPAL_BODY = <<~XML
      <d:propfind xmlns:d="DAV:"><d:prop><d:current-user-principal/></d:prop></d:propfind>
    XML

    CALENDAR_HOME_BODY = <<~XML
      <d:propfind xmlns:d="DAV:" xmlns:c="urn:ietf:params:xml:ns:caldav">
        <d:prop><c:calendar-home-set/></d:prop>
      </d:propfind>
    XML

    CALENDAR_LIST_BODY = <<~XML
      <d:propfind xmlns:d="DAV:" xmlns:c="urn:ietf:params:xml:ns:caldav">
        <d:prop>
          <d:resourcetype/>
          <d:displayname/>
          <c:supported-calendar-component-set/>
        </d:prop>
      </d:propfind>
    XML

    class Propfind < Net::HTTPRequest
      METHOD = 'PROPFIND'
      REQUEST_HAS_BODY = true
      RESPONSE_HAS_BODY = true
    end

    class Report < Net::HTTPRequest
      METHOD = 'REPORT'
      REQUEST_HAS_BODY = true
      RESPONSE_HAS_BODY = true
    end

    def events(from:, to:)
      calendars.flat_map { |calendar| events_in(calendar, from, to) }
    end

    # Exposed so the connection form can show what was found after a save.
    def calendars
      configured = Array(setting('calendar_urls')).compact_blank
      return configured.map { |url| { url: url, name: setting('label').presence || 'Calendar' } } if configured.any?

      Rails.cache.fetch(discovery_cache_key, expires_in: DISCOVERY_TTL) { discover_calendars }
    end

    private

    # --- Discovery ----------------------------------------------------------

    def discover_calendars
      home = calendar_home
      raise Unavailable, 'could not locate a calendar home on this server' if home.blank?

      doc = propfind(home, depth: 1, body: CALENDAR_LIST_BODY)

      responses(doc).filter_map do |response|
        next unless calendar_collection?(response)

        href = response.at_xpath('./d:href', NAMESPACES)&.text
        next if href.blank?

        { url: absolute(href, home), name: display_name(response) }
      end
    end

    def calendar_home
      root, doc = principal_document
      principal = property_text(doc, './/d:current-user-principal/d:href')
      # Some servers answer the principal query straight from the given URL.
      return root if principal.blank?

      principal_url = absolute(principal, root)
      home = property_text(propfind(principal_url, depth: 0, body: CALENDAR_HOME_BODY),
                           './/c:calendar-home-set/d:href')

      home.present? ? absolute(home, principal_url) : root
    end

    # Finds a URL on this server that actually answers a principal PROPFIND, and
    # returns it alongside that answer.
    #
    # What people paste is rarely the DAV root. Fastmail's own documented
    # address is https://caldav.fastmail.com/dav, which answers 401 to an
    # unauthenticated PROPFIND — so it looks right — and then 405 once the
    # credentials are accepted, because the collection lives one level down.
    # RFC 6764 exists for exactly this: ask /.well-known/caldav and follow where
    # it points. The configured URL is still tried first, so a server that needs
    # a specific path keeps working.
    def discovery_roots
      origin = URI.parse(base_url).then { |u| "#{u.scheme}://#{u.host}#{":#{u.port}" if u.port != u.default_port}" }

      [base_url, "#{origin}/.well-known/caldav", "#{origin}/"].uniq
    rescue URI::Error
      [base_url]
    end

    def principal_document
      failure = nil

      discovery_roots.each do |root|
        return [root, propfind(root, depth: 0, body: PRINCIPAL_BODY)]
      rescue Unavailable => e
        # 404/405 means "not a DAV collection", which is a reason to try the
        # next candidate. A refused credential is not, and must not be retried
        # against every path in turn.
        failure ||= e
        Rails.logger.info("[caldav] #{root} did not answer a principal query: #{e.message}")
      end

      # Re-raised as captured. `raise failure, 'message'` would rebuild it with
      # the new message and throw away the status that says what went wrong.
      raise failure if failure

      raise Unavailable, 'no CalDAV collection found on this server'
    end

    def calendar_collection?(response)
      return false if response.at_xpath('.//d:resourcetype/c:calendar', NAMESPACES).nil?

      components = response.xpath('.//c:supported-calendar-component-set/c:comp', NAMESPACES)
      components.empty? || components.any? { |comp| comp['name'].to_s.casecmp('VEVENT').zero? }
    end

    def display_name(response)
      response.at_xpath('.//d:displayname', NAMESPACES)&.text.presence || 'Calendar'
    end

    # --- Event fetching -----------------------------------------------------

    def events_in(calendar, from, to)
      expanded = true
      doc = begin
        report(calendar[:url], query_body(from, to, expand: true))
      rescue Unavailable, AuthenticationError => e
        raise if e.is_a?(AuthenticationError)

        # Not every server implements <c:expand>; retry unexpanded and do the
        # recurrence work here instead.
        Rails.logger.info("[caldav] #{calendar[:name]} rejected expand, falling back: #{e.message}")
        expanded = false
        report(calendar[:url], query_body(from, to, expand: false))
      end

      events = calendar_data(doc).flat_map do |ics|
        Meetings::IcsParser.parse(ics, calendar_name: calendar[:name], zone: zone, user_email: username)
      end

      expanded ? events : Meetings::RecurrenceExpander.expand(events, from: from, to: to)
    end

    def calendar_data(doc)
      doc.xpath('//c:calendar-data', NAMESPACES).map(&:text).compact_blank
    end

    # --- Request bodies -----------------------------------------------------

    def query_body(from, to, expand:)
      range = %(start="#{ical_time(from)}" end="#{ical_time(to)}")
      calendar_data = expand ? "<c:calendar-data><c:expand #{range}/></c:calendar-data>" : '<c:calendar-data/>'

      <<~XML
        <c:calendar-query xmlns:d="DAV:" xmlns:c="urn:ietf:params:xml:ns:caldav">
          <d:prop><d:getetag/>#{calendar_data}</d:prop>
          <c:filter>
            <c:comp-filter name="VCALENDAR">
              <c:comp-filter name="VEVENT"><c:time-range #{range}/></c:comp-filter>
            </c:comp-filter>
          </c:filter>
        </c:calendar-query>
      XML
    end

    def ical_time(time)
      time.utc.strftime('%Y%m%dT%H%M%SZ')
    end

    # --- Transport ----------------------------------------------------------

    def propfind(url, depth:, body:)
      parse_xml(request(Propfind, url, body, { 'Depth' => depth.to_s }))
    end

    # forbidden_is_auth is false here: a server that doesn't implement the
    # report it was handed answers 403 with a supported-report precondition,
    # which is indistinguishable by status alone from a permissions problem.
    # Discovery has already proven these credentials work by this point, so 403
    # on a REPORT means "not that report" and should fall back, not sign out.
    def report(url, body)
      parse_xml(request(Report, url, body, { 'Depth' => '1' }, forbidden_is_auth: false))
    end

    def request(request_class, url, body, headers = {}, forbidden_is_auth: true)
      remaining_redirects = MAX_REDIRECTS
      current_url = url

      loop do
        response = perform(request_class, URI.parse(current_url), body, headers)

        case response
        when Net::HTTPRedirection
          raise Unavailable, 'too many redirects' if remaining_redirects.zero?

          remaining_redirects -= 1
          current_url = absolute(response['location'], current_url)
        when Net::HTTPUnauthorized
          raise AuthenticationError, "CalDAV credentials rejected (#{response.code})"
        when Net::HTTPForbidden
          raise AuthenticationError, "CalDAV credentials rejected (#{response.code})" if forbidden_is_auth

          raise Unavailable, "CalDAV server refused this request (#{response.code})"
        when Net::HTTPSuccess
          return response.body
        else
          raise Unavailable, "CalDAV server returned #{response.code}"
        end
      end
    end

    def perform(request_class, uri, body, headers)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == 'https'
      http.open_timeout = OPEN_TIMEOUT
      http.read_timeout = READ_TIMEOUT

      request = request_class.new(uri.request_uri)
      request.basic_auth(username, password)
      request['Content-Type'] = 'application/xml; charset=utf-8'
      headers.each { |key, value| request[key] = value }
      request.body = body

      http.request(request)
    rescue Net::OpenTimeout, Net::ReadTimeout, SocketError, Errno::ECONNREFUSED, OpenSSL::SSL::SSLError => e
      raise Unavailable, "CalDAV request failed: #{e.class}: #{e.message}"
    end

    # --- Helpers ------------------------------------------------------------

    def parse_xml(body)
      Nokogiri::XML(body.to_s)
    end

    # Only props the server actually returned with a 2xx propstat are real; a
    # 404 propstat block carries an empty element of the same name.
    def responses(doc)
      doc.xpath('//d:response', NAMESPACES).select do |response|
        response.xpath('./d:propstat/d:status', NAMESPACES).any? { |s| s.text.include?(' 200 ') }
      end
    end

    def property_text(doc, xpath)
      responses(doc).filter_map { |response| response.at_xpath(xpath, NAMESPACES)&.text.presence }.first
    end

    def absolute(href, base)
      URI.join(base, href).to_s
    rescue URI::Error
      href
    end

    def base_url
      url = setting('url').to_s.strip
      raise Unavailable, 'no CalDAV server URL configured' if url.blank?

      url
    end

    def username
      credentials['username']
    end

    def password
      credentials['password']
    end

    def discovery_cache_key
      "caldav/calendars/#{connection.id}/#{Digest::SHA256.hexdigest(base_url)}"
    end
  end
end
