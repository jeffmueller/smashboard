# A throwaway Slack API for developing the Slack panel without registering an
# app or installing it to a workspace.
#
#   ruby script/slack_stub.rb                       # listens on 127.0.0.1:4611
#   SLACK_BASE_URL=http://127.0.0.1:4611 bin/dev
#
# Then add a `slack` connection with any user token. Serves auth.test,
# users.conversations, conversations.info and users.info — including Slack's
# habit of reporting failures as HTTP 200 with {"ok": false}.
require 'socket'
require 'json'
require 'cgi'

PORT = 4611
TEAM = { name: 'Acme', id: 'T0ACME', url: 'https://acme.slack.com/' }.freeze

USERS = {
  'U_DANA' => 'Dana Lee',
  'U_SAM' => 'Sam Okafor',
  'U_RILEY' => 'Riley Chen'
}.freeze

# unread is the display count Slack badges with; raw is the noisier total.
CONVERSATIONS = [
  { id: 'D_DANA', is_im: true, user: 'U_DANA', unread: 4, raw: 9 },
  { id: 'D_SAM', is_im: true, user: 'U_SAM', unread: 2, raw: 2 },
  { id: 'D_RILEY', is_im: true, user: 'U_RILEY', unread: 0, raw: 0 },
  { id: 'G_STANDUP', is_mpim: true, name: 'mpdm-demo--dana--sam', unread: 1, raw: 3 },
  { id: 'C_ENG', name: 'engineering', unread: 12, raw: 48 },
  { id: 'C_GENERAL', name: 'general', unread: 3, raw: 31 },
  { id: 'C_RANDOM', name: 'random', unread: 0, raw: 17 },
  { id: 'C_DEPLOYS', name: 'deploys', unread: 6, raw: 6 },
  # No unread keys at all — what Slack does for a channel when the token lacks
  # the history scopes. Exercises the "couldn't be counted" path.
  { id: 'C_SILENT', name: 'silent-channel', unread: nil, raw: nil }
].freeze

def listing
  CONVERSATIONS.map do |conversation|
    { id: conversation[:id], name: conversation[:name],
      is_im: conversation[:is_im] || false, is_mpim: conversation[:is_mpim] || false,
      is_channel: !(conversation[:is_im] || conversation[:is_mpim]) }.compact
  end
end

def info_for(id)
  conversation = CONVERSATIONS.find { |c| c[:id] == id }
  return { ok: false, error: 'channel_not_found' } if conversation.nil?

  { ok: true,
    channel: { id: conversation[:id], name: conversation[:name], user: conversation[:user],
               unread_count: conversation[:raw],
               unread_count_display: conversation[:unread] }.compact }
end

server = TCPServer.new('127.0.0.1', PORT)
puts "slack stub listening on #{PORT}"
$stdout.flush

loop do
  socket = server.accept
  request_line = socket.gets
  next socket.close if request_line.nil?

  _method, target, = request_line.split
  while (line = socket.gets) && line != "\r\n"
    # headers are irrelevant here
  end

  path, query = target.split('?', 2)
  params = CGI.parse(query.to_s)

  payload =
    case path
    when '/api/auth.test'
      { ok: true, team: TEAM[:name], team_id: TEAM[:id], user: 'demo', url: TEAM[:url] }
    when '/api/users.conversations'
      { ok: true, channels: listing, response_metadata: { next_cursor: '' } }
    when '/api/conversations.info'
      info_for(params['channel']&.first)
    when '/api/users.info'
      id = params['user']&.first
      USERS.key?(id) ? { ok: true, user: { real_name: USERS[id], profile: {} } }
                     : { ok: false, error: 'user_not_found' }
    else
      { ok: false, error: 'unknown_method' }
    end

  body = JSON.generate(payload).b
  # Slack answers everything with 200, errors included.
  socket.write("HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: #{body.bytesize}\r\n" \
               "Connection: close\r\n\r\n")
  socket.write(body)
  socket.close
end
