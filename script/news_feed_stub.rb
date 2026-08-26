# A throwaway breaking-news feed for developing the news panel without pointing
# it at a real service.
#
#   ruby script/news_feed_stub.rb                   # listens on 127.0.0.1:4711
#
# Then add a `news_feed` connection with feed URL http://127.0.0.1:4711, cookie
# name `auth` and any password. Serves the whole contract the panel expects:
#
#   GET /api/breaking-news
#   -> { headline, summary, mentionCount, sources, articles[] }
#
# The headline advances every 45 seconds so the panel's "only notify when the
# story changes" behaviour is visible without waiting for real news, and the
# shared-password cookie is checked so the auth path is exercised too.
require 'socket'
require 'json'

PORT = 4711

STORIES = [
  { headline: 'Power restored across the eastern grid',
    summary: 'Utilities report the last substations back online after nine hours.',
    mention_count: 47,
    sources: %w[Reuters AP Bloomberg],
    articles: [
      { source: 'Reuters', title: 'Grid operators confirm full restoration',
        link: 'https://example.com/grid-restored' },
      { source: 'AP', title: 'What caused the cascade', link: 'https://example.com/cascade' }
    ] },
  { headline: 'Talks resume after weekend recess',
    summary: 'Negotiators return to the table with a narrowed agenda.',
    mention_count: 23,
    sources: %w[AP Guardian],
    articles: [
      { source: 'AP', title: 'Both sides describe progress', link: 'https://example.com/talks' }
    ] }
].freeze

def story
  # Rotates on a wall-clock bucket so every request in the same window agrees.
  STORIES[(Time.now.to_i / 45) % STORIES.size]
end

def payload
  s = story
  { headline: s[:headline], summary: s[:summary], mentionCount: s[:mention_count],
    sources: s[:sources], articles: s[:articles] }
end

def respond(client, status, body)
  client.print "HTTP/1.1 #{status}\r\n"
  client.print "Content-Type: application/json\r\n"
  client.print "Content-Length: #{body.bytesize}\r\n"
  client.print "Connection: close\r\n\r\n"
  client.print body
end

server = TCPServer.new('127.0.0.1', PORT)
puts "news feed stub on http://127.0.0.1:#{PORT} (GET /api/breaking-news)"
$stdout.flush

loop do
  client = server.accept
  request = client.gets.to_s
  headers = {}
  while (line = client.gets) && line != "\r\n"
    key, _, value = line.partition(':')
    headers[key.strip.downcase] = value.strip
  end

  path = request.split[1].to_s

  if !path.start_with?('/api/breaking-news')
    respond(client, '404 Not Found', { error: 'not found' }.to_json)
  elsif headers['cookie'].to_s.empty?
    # The real thing gates every route on the shared password, so the stub does
    # too — otherwise a client that forgets the cookie looks like it works.
    respond(client, '401 Unauthorized', { error: 'missing auth cookie' }.to_json)
  else
    respond(client, '200 OK', payload.to_json)
  end

  client.close
rescue StandardError => e
  warn "news_feed_stub: #{e.class}: #{e.message}"
  client&.close
end
