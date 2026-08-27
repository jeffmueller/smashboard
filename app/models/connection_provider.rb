# frozen_string_literal: true

# What each kind of connection needs, and how to explain it.
#
# This is the catalogue the connection form renders from: it drives which fields
# appear for a given provider, what each one means, and where to go and get the
# credential. Adding an integration means adding an entry here — the form needs
# no changes.
class ConnectionProvider
  Field = Struct.new(:key, :label, :hint, :placeholder, :optional, :secret, keyword_init: true) do
    def optional? = !!optional
    def secret? = !!secret
  end

  CATALOG = {
    'imap' => {
      label: 'Mailbox (IMAP)',
      panel: 'Email',
      summary: 'Unread counts and message previews for one mailbox. Read-only — nothing here can mark mail read.',
      guidance: 'Works with Fastmail, Gmail, iCloud, Outlook and anything else that speaks IMAP. ' \
                'Add one connection per mailbox.',
      settings: [
        { key: 'host', label: 'Server', optional: true, placeholder: 'imap.fastmail.com',
          hint: 'Leave blank and it is worked out from your address — Gmail, Fastmail, iCloud, ' \
                'Outlook and Yahoo are recognised.' },
        { key: 'port', label: 'Port', optional: true, placeholder: '993',
          hint: 'Defaults to 993.' },
        { key: 'mailbox', label: 'Folder', optional: true, placeholder: 'INBOX',
          hint: 'Defaults to INBOX.' },
        { key: 'ssl', label: 'Use TLS', optional: true, placeholder: 'true',
          hint: 'Leave blank unless you are connecting to a server on your own network without TLS.' }
      ],
      credentials: [
        { key: 'username', label: 'Email address', placeholder: 'you@fastmail.com' },
        { key: 'password', label: 'App password', secret: true,
          hint: 'Not your account password. Fastmail: Settings → Privacy & Security → App passwords, ' \
                'scoped to IMAP. Gmail: an App Password, which needs 2FA switched on.' }
      ]
    },

    'gmail' => {
      label: 'Gmail',
      panel: 'Email',
      oauth: :google,
      # gmail.readonly, deliberately, rather than the https://mail.google.com/
      # scope IMAP would need — that one also grants send and delete, which a
      # panel counting unread messages has no business holding.
      oauth_scopes: ['https://www.googleapis.com/auth/gmail.readonly'],
      summary: 'Unread counts and message previews for a Gmail account. Read-only.',
      guidance: 'Sign in with Google — no app password needed. Reads only; it cannot send, ' \
                'delete or mark anything read.',
      settings: [
        { key: 'query', label: 'Search', optional: true, placeholder: 'is:unread in:inbox',
          hint: 'Any Gmail search. Defaults to unread mail in your inbox — narrow it with ' \
                'something like "is:unread in:inbox -category:promotions".' }
      ],
      credentials: []
    },

    'caldav' => {
      label: 'Calendar (CalDAV)',
      panel: 'Meetings',
      summary: "Today's meetings from a CalDAV server, with join links for video calls.",
      guidance: 'Fastmail and most self-hosted calendars. Your calendars are discovered automatically — ' \
                'you only need the server address.',
      settings: [
        { key: 'url', label: 'Server URL', placeholder: 'https://caldav.fastmail.com/dav/',
          hint: 'For Fastmail this exact address works.' }
      ],
      credentials: [
        { key: 'username', label: 'Username', placeholder: 'you@fastmail.com' },
        { key: 'password', label: 'App password', secret: true,
          hint: 'Fastmail: Settings → Privacy & Security → App passwords, scoped to CalDAV.' }
      ]
    },

    'google_calendar' => {
      label: 'Google Calendar',
      panel: 'Meetings',
      oauth: :google,
      oauth_scopes: ['https://www.googleapis.com/auth/calendar.readonly'],
      summary: "Today's meetings from Google, with Meet links.",
      guidance: 'Sign in with Google and the token is stored for you. ' \
                'The server needs GOOGLE_CLIENT_ID and GOOGLE_CLIENT_SECRET set.',
      settings: [
        { key: 'calendar_ids', label: 'Calendar IDs', optional: true,
          placeholder: 'primary, work@group.calendar.google.com',
          hint: 'Comma separated. Leave blank for every calendar you have selected in Google.' }
      ],
      credentials: []
    },

    'github' => {
      label: 'GitHub',
      panel: 'GitHub and Pull Requests',
      summary: 'Unread notifications, plus pull requests you opened or that are waiting on your review.',
      guidance: 'Create a personal access token at github.com → Settings → Developer settings. ' \
                'It needs the notifications scope, plus repo if you want private repositories included.',
      settings: [
        { key: 'api_endpoint', label: 'API endpoint', optional: true, placeholder: 'https://ghe.example.com/api/v3/',
          hint: 'Only for GitHub Enterprise. Leave blank for github.com.' }
      ],
      credentials: [
        { key: 'access_token', label: 'Personal access token', secret: true, placeholder: 'ghp_…' }
      ]
    },

    'slack' => {
      label: 'Slack',
      panel: 'Slack',
      oauth: :slack,
      # The :history scopes are not about reading messages — they are what makes
      # conversations.info return an unread count for channels at all. Without
      # them DMs count and channels silently report nothing.
      oauth_scopes: %w[channels:read groups:read im:read mpim:read
                       channels:history groups:history im:history mpim:history],
      summary: 'Unread message counts for one workspace, direct messages counted first.',
      guidance: 'Sign in with Slack and the user token is stored for you. ' \
                'Add one connection per workspace. The server needs SLACK_CLIENT_ID and ' \
                'SLACK_CLIENT_SECRET set.',
      settings: [
        { key: 'lookup_budget', label: 'Conversations to check', optional: true, placeholder: '40',
          hint: 'Slack has no bulk unread endpoint, so each conversation is asked separately. ' \
                'Raise this for a large workspace at the cost of more API calls.' }
      ],
      credentials: []
    },

    'nws' => {
      label: 'Weather alerts (NWS)',
      panel: 'Weather',
      summary: 'Active National Weather Service alerts, current conditions and a radar loop.',
      guidance: 'No API key and no account. It uses the postal code on your profile unless you set ' \
                'coordinates here. US only.',
      settings: [
        { key: 'postal_code', label: 'Postal code', optional: true, placeholder: '10001',
          hint: 'Leave blank to use the one on your account.' },
        { key: 'latitude', label: 'Latitude', optional: true, placeholder: '38.8894',
          hint: 'Set both coordinates for a precise spot; they win over a postal code.' },
        { key: 'longitude', label: 'Longitude', optional: true, placeholder: '-77.0352' }
      ],
      credentials: []
    },

    'weather_station' => {
      label: 'Personal weather station',
      panel: 'Weather',
      summary: 'Readings from your own station, used in preference to the nearest NWS station.',
      guidance: 'WeatherFlow Tempest. Create a personal access token at tempestwx.com → Settings → ' \
                'Data Authorizations.',
      settings: [
        { key: 'vendor', label: 'Vendor', optional: true, placeholder: 'tempest',
          hint: 'Only tempest is supported today; leave blank for it.' },
        { key: 'station_id', label: 'Station ID', optional: true, placeholder: '12345',
          hint: 'Leave blank to use the first station on the account.' }
      ],
      credentials: [
        { key: 'token', label: 'Personal access token', secret: true }
      ]
    },

    'home_assistant' => {
      label: 'Home Assistant',
      panel: 'Cameras',
      summary: 'Live camera snapshots, proxied through smashboard so the token never reaches the browser.',
      guidance: 'Create a long-lived access token in Home Assistant under your profile → Security. ' \
                'Cameras already configured in Home Assistant are discovered automatically.',
      settings: [
        { key: 'base_url', label: 'Home Assistant URL', placeholder: 'http://homeassistant.local:8123',
          hint: 'Must be reachable from the machine running smashboard, not from your phone.' },
        { key: 'entity_ids', label: 'Cameras to show', optional: true,
          placeholder: 'camera.front_door, camera.driveway',
          hint: 'Comma separated. Leave blank for every camera, or list them to choose the order.' }
      ],
      credentials: [
        { key: 'access_token', label: 'Long-lived access token', secret: true }
      ]
    },

    'news_feed' => {
      label: 'Breaking news feed',
      panel: 'Breaking News',
      summary: 'The top developing story, read from a JSON endpoint you point it at.',
      guidance: 'Works with any server answering GET /api/breaking-news with a JSON object of ' \
                'headline, summary, mentionCount, sources and articles. If that endpoint sits ' \
                'behind a shared password, put the password below and name the cookie the server ' \
                'expects to find it in.',
      settings: [
        { key: 'base_url', label: 'Feed URL', placeholder: 'https://news.example.com',
          hint: 'The site root — /api/breaking-news is appended to it.' },
        { key: 'cookie_name', label: 'Password cookie', optional: true, placeholder: 'auth',
          hint: 'The cookie your feed reads the shared password from. Defaults to "auth".' }
      ],
      credentials: [
        { key: 'password', label: 'Shared password', secret: true,
          hint: 'Sent as the cookie named above, and encrypted at rest. ' \
                'Leave blank for a feed that needs no password.' }
      ]
    }
  }.freeze

  attr_reader :key, :label, :panel, :summary, :guidance, :settings, :credentials, :oauth, :oauth_scopes

  class << self
    def all
      @all ||= CATALOG.map { |key, attributes| new(key, attributes) }
    end

    def find(key)
      by_key[key.to_s]
    end

    # Not `delegate :keys, to: :CATALOG` — delegate sends the target as a
    # method, and CATALOG is a constant, so that raises NameError.
    def keys
      CATALOG.keys
    end

    # Grouped for the picker, so related integrations sit together.
    def by_panel
      all.group_by(&:panel)
    end

    private

    def by_key
      @by_key ||= all.index_by(&:key)
    end
  end

  def initialize(key, attributes)
    @key = key
    @oauth = attributes[:oauth]
    @oauth_scopes = Array(attributes[:oauth_scopes])
    @label = attributes[:label]
    @panel = attributes[:panel]
    @summary = attributes[:summary]
    @guidance = attributes[:guidance]
    @settings = build(attributes[:settings])
    @credentials = build(attributes[:credentials]).map { |field| field.tap { |f| f.secret = true } }
  end

  # Providers whose credential arrives through an authorization flow rather
  # than being typed in.
  def oauth?
    oauth.present?
  end

  def field_keys
    { settings: settings.map(&:key), credentials: credentials.map(&:key) }
  end

  private

  def build(fields)
    Array(fields).map { |attributes| Field.new(**attributes) }
  end
end
