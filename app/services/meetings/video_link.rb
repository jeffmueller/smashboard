# frozen_string_literal: true

module Meetings
  # Digs the "join the call" URL out of a calendar event.
  #
  # There is no standard field for this. Google puts it in conferenceData or
  # hangoutLink; Outlook buries it in an HTML description; plenty of people just
  # paste a Zoom URL into LOCATION. So callers hand over every candidate string
  # they have, in priority order, and the first recognised provider URL wins.
  #
  # Ordering matters more than it looks: a Zoom invite body contains the join
  # URL, a dial-in page, a "one tap mobile" link and often a support link, so
  # scanning a description for "any URL" reliably picks the wrong one. Only
  # known meeting-provider patterns are matched.
  class VideoLink
    Result = Struct.new(:url, :provider, keyword_init: true)

    # Trailing characters that regularly get glued onto a URL by surrounding
    # prose or markup, and are never part of the link itself.
    TRAILING_JUNK = /[)\]>,.;'"]+\z/

    PROVIDERS = [
      { name: 'Zoom', pattern: %r{https?://(?:[\w-]+\.)*(?:zoom\.us|zoomgov\.com)/(?:j|s|my|w|wc/join)/[^\s<>"']+}i },
      { name: 'Google Meet', pattern: %r{https?://meet\.google\.com/[^\s<>"']+}i },
      { name: 'Microsoft Teams', pattern: %r{https?://teams\.(?:microsoft|live)\.com/[^\s<>"']+}i },
      { name: 'Webex', pattern: %r{https?://(?:[\w-]+\.)*webex\.com/[^\s<>"']+}i },
      { name: 'Whereby', pattern: %r{https?://(?:[\w-]+\.)*whereby\.com/[^\s<>"']+}i },
      { name: 'Jitsi', pattern: %r{https?://meet\.jit\.si/[^\s<>"']+}i },
      { name: 'GoTo', pattern: %r{https?://(?:[\w-]+\.)*(?:gotomeeting|goto)\.com/(?:join|meeting)/[^\s<>"']+}i },
      { name: 'BlueJeans', pattern: %r{https?://(?:[\w-]+\.)*bluejeans\.com/[^\s<>"']+}i },
      { name: 'Chime', pattern: %r{https?://(?:[\w-]+\.)*chime\.aws/[^\s<>"']+}i },
      { name: 'Around', pattern: %r{https?://(?:[\w-]+\.)*around\.co/[^\s<>"']+}i },
      { name: 'Discord', pattern: %r{https?://(?:[\w-]+\.)*discord\.(?:gg|com)/[^\s<>"']+}i },
      { name: 'Slack', pattern: %r{https?://(?:[\w-]+\.)*slack\.com/huddle/[^\s<>"']+}i }
    ].freeze

    class << self
      # Sources are tried in the order given; pass the most authoritative first
      # (an explicit conference field before a free-text description).
      def extract(*sources)
        sources.flatten.compact_blank.each do |source|
          text = normalize(source)
          PROVIDERS.each do |provider|
            match = text[provider[:pattern]]
            next if match.blank?

            return Result.new(url: clean(match), provider: provider[:name])
          end
        end

        nil
      end

      private

      # Descriptions arrive as HTML often enough that entity-encoded query
      # separators (&amp;) would otherwise corrupt the URL, and ICS folding
      # inserts literal "\n" escapes mid-string.
      #
      # Link targets are lifted out of href/src attributes *before* tags are
      # stripped — an Outlook description puts the join URL only in the anchor's
      # href, so stripping tags first would throw away the very thing we want.
      def normalize(source)
        text = CGI.unescapeHTML(source.to_s.gsub('\\n', "\n").gsub('\\,', ','))

        # Hoisted ahead of the visible text because they're the more
        # authoritative source: an Outlook invite renders "Click here to join"
        # and carries the real URL only in the anchor.
        hrefs = text.scan(/\b(?:href|src)=["']([^"']+)["']/i).flatten

        (hrefs << text.gsub(/<[^>]+>/, ' ')).join("\n")
      end

      def clean(url)
        url.sub(TRAILING_JUNK, '')
      end
    end
  end
end
