# A throwaway CalDAV server for developing the calendar panel without needing
# real Fastmail or Google credentials.
#
#   ruby script/caldav_stub.rb        # listens on 127.0.0.1:4111
#
# Then add a `caldav` connection with url http://127.0.0.1:4111/ and any
# username/password. It implements just enough of RFC 4791 to exercise the real
# client end to end: the principal -> calendar-home -> calendar-list discovery
# walk, and a calendar-query REPORT returning two calendars of events with Zoom,
# Google Meet and Teams links. Event times are relative to now.
require 'socket'
require 'date'

PORT = 4111
today = Date.today

def multistatus(inner)
  %(<?xml version="1.0" encoding="utf-8"?>\n<d:multistatus xmlns:d="DAV:" xmlns:c="urn:ietf:params:xml:ns:caldav">#{inner}</d:multistatus>)
end

PRINCIPAL = multistatus(<<~XML)
  <d:response><d:href>/</d:href><d:propstat>
    <d:prop><d:current-user-principal><d:href>/principals/user/alex/</d:href></d:current-user-principal></d:prop>
    <d:status>HTTP/1.1 200 OK</d:status>
  </d:propstat></d:response>
XML

HOME = multistatus(<<~XML)
  <d:response><d:href>/principals/user/alex/</d:href><d:propstat>
    <d:prop><c:calendar-home-set><d:href>/calendars/user/alex/</d:href></c:calendar-home-set></d:prop>
    <d:status>HTTP/1.1 200 OK</d:status>
  </d:propstat></d:response>
XML

CALENDARS = multistatus(<<~XML)
  <d:response><d:href>/calendars/user/alex/work/</d:href><d:propstat>
    <d:prop>
      <d:resourcetype><d:collection/><c:calendar/></d:resourcetype>
      <d:displayname>Work</d:displayname>
      <c:supported-calendar-component-set><c:comp name="VEVENT"/></c:supported-calendar-component-set>
    </d:prop>
    <d:status>HTTP/1.1 200 OK</d:status>
  </d:propstat></d:response>
  <d:response><d:href>/calendars/user/alex/family/</d:href><d:propstat>
    <d:prop>
      <d:resourcetype><d:collection/><c:calendar/></d:resourcetype>
      <d:displayname>Family</d:displayname>
      <c:supported-calendar-component-set><c:comp name="VEVENT"/></c:supported-calendar-component-set>
    </d:prop>
    <d:status>HTTP/1.1 200 OK</d:status>
  </d:propstat></d:response>
XML

def utc(offset_minutes)
  (Time.now.utc + (offset_minutes * 60)).strftime('%Y%m%dT%H%M%SZ')
end

# Times are emitted in UTC relative to now, so the panel always has a realistic
# mix of in-progress and upcoming meetings whenever this is run.
def ics_for(date, which)
  events =
    if which == :work
      <<~ICS
        BEGIN:VEVENT
        UID:standup@stub
        SUMMARY:Engineering Standup
        DTSTART:#{utc(-10)}
        DTEND:#{utc(20)}
        LOCATION:https://acme.zoom.us/j/98765432101?pwd=abcDEF
        ORGANIZER;CN=Dana Lee:mailto:dana@example.com
        END:VEVENT
        BEGIN:VEVENT
        UID:review@stub
        SUMMARY:Design Review
        DTSTART:#{utc(55)}
        DTEND:#{utc(115)}
        LOCATION:Room 4B
        X-GOOGLE-CONFERENCE:https://meet.google.com/abc-defg-hij
        DESCRIPTION:Bring the mockups.\\nHelp: https://support.zoom.us/hc/en-us
        END:VEVENT
        BEGIN:VEVENT
        UID:retro@stub
        SUMMARY:Sprint Retro
        DTSTART:#{utc(160)}
        DTEND:#{utc(220)}
        LOCATION:https://teams.microsoft.com/l/meetup-join/19%3ameeting_abc%40thread.v2/0
        END:VEVENT
        BEGIN:VEVENT
        UID:done@stub
        SUMMARY:Early Sync
        DTSTART:#{utc(-180)}
        DTEND:#{utc(-165)}
        END:VEVENT
      ICS
    else
      <<~ICS
        BEGIN:VEVENT
        UID:dentist@stub
        SUMMARY:Dentist
        DTSTART:#{utc(250)}
        DTEND:#{utc(295)}
        LOCATION:412 Main St
        END:VEVENT
        BEGIN:VEVENT
        UID:holiday@stub
        SUMMARY:School Holiday
        DTSTART;VALUE=DATE:#{date.strftime('%Y%m%d')}
        DTEND;VALUE=DATE:#{(date + 1).strftime('%Y%m%d')}
        END:VEVENT
      ICS
    end
  "BEGIN:VCALENDAR\nVERSION:2.0\nPRODID:-//stub//EN\n#{events}END:VCALENDAR\n"
end

def calendar_data(ics)
  escaped = ics.gsub('&', '&amp;').gsub('<', '&lt;')
  multistatus(%(<d:response><d:href>/e.ics</d:href><d:propstat><d:prop><c:calendar-data>#{escaped}</c:calendar-data></d:prop><d:status>HTTP/1.1 200 OK</d:status></d:propstat></d:response>))
end

server = TCPServer.new('127.0.0.1', PORT)
puts "caldav stub listening on #{PORT}"
$stdout.flush

loop do
  client = server.accept
  request_line = client.gets
  # A bare TCP connect with no request line — a port probe, a browser
  # preconnect — must close that one connection, not end the server.
  next client.close if request_line.nil?

  method, path, = request_line.split
  next client.close if path.nil?
  headers = {}
  while (line = client.gets) && line != "\r\n"
    key, value = line.split(': ', 2)
    headers[key.downcase] = value.to_s.strip
  end
  client.read(headers['content-length'].to_i) if headers['content-length']

  body =
    if method == 'PROPFIND' && path == '/'
      PRINCIPAL
    elsif method == 'PROPFIND' && path.include?('principals')
      HOME
    elsif method == 'PROPFIND'
      CALENDARS
    elsif method == 'REPORT'
      calendar_data(ics_for(today, path.include?('family') ? :family : :work))
    else
      multistatus('')
    end

  client.print("HTTP/1.1 207 Multi-Status\r\nContent-Type: application/xml; charset=utf-8\r\nContent-Length: #{body.bytesize}\r\nConnection: close\r\n\r\n#{body}")
  client.close
end
