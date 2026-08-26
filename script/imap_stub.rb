# A throwaway IMAP server for developing the email panel without a real mailbox.
#
#   ruby script/imap_stub.rb          # listens on 127.0.0.1:1143, no TLS
#
# Then add an `imap` connection with host 127.0.0.1, port 1143, ssl false, and
# any username/password. It implements just enough of RFC 3501 to exercise the
# real net-imap client end to end: LOGIN, STATUS, EXAMINE, UID SEARCH and the
# UID FETCH the panel actually issues, including literal-encoded body parts.
require 'socket'

PORT = 1143
MAILBOX_UNSEEN = 12

MESSAGES = [
  { uid: 101, seq: 1, from_name: 'Dana Lee', mailbox: 'dana', host: 'example.com',
    subject: 'Standup moved to 10:15', date: '25-Aug-2026 13:30:00 +0000',
    content_type: 'text/plain; charset=UTF-8', encoding: nil,
    body: "Hi all,\r\n\r\nPushing standup back fifteen minutes tomorrow.\r\n\r\nDana\r\n" },
  { uid: 102, seq: 2, from_name: 'Fastmail', mailbox: 'noreply', host: 'fastmail.com',
    subject: '=?UTF-8?B?WW91ciBiYWNrdXAgaXMgcmVhZHkg4pyT?=', date: '25-Aug-2026 12:05:00 +0000',
    content_type: 'text/html; charset=UTF-8', encoding: nil,
    body: "<html><body><p>Your monthly <b>backup</b> finished successfully.</p></body></html>\r\n" },
  { uid: 103, seq: 3, from_name: nil, mailbox: 'billing', host: 'utility.example',
    subject: 'Statement available', date: '25-Aug-2026 09:41:00 +0000',
    content_type: 'text/plain; charset=UTF-8', encoding: 'quoted-printable',
    body: "Your statement for Caf=C3=A9 Power is ready=2E Amount due: =C2=A342=2E17\r\n" }
].freeze

def quoted(value)
  value.nil? ? 'NIL' : %("#{value.to_s.gsub('\\', '\\\\\\\\').gsub('"', '\\"')}")
end

def address(message)
  %((#{quoted(message[:from_name])} NIL #{quoted(message[:mailbox])} #{quoted(message[:host])}))
end

def envelope(message)
  from = "(#{address(message)})"
  to = %(((NIL NIL "alex" "example.com")))
  [
    '(', quoted(message[:date]), ' ', quoted(message[:subject]), ' ',
    from, ' ', from, ' ', from, ' ', to, ' NIL NIL NIL ',
    quoted("<#{message[:uid]}@example.com>"), ')'
  ].join
end

def literal(data)
  "{#{data.bytesize}}\r\n#{data}"
end

def fetch_response(message)
  headers = +"Content-Type: #{message[:content_type]}\r\n"
  headers << "Content-Transfer-Encoding: #{message[:encoding]}\r\n" if message[:encoding]

  "* #{message[:seq]} FETCH (UID #{message[:uid]} " \
    "INTERNALDATE #{quoted(message[:date])} " \
    "ENVELOPE #{envelope(message)} " \
    "BODY[HEADER.FIELDS (CONTENT-TYPE CONTENT-TRANSFER-ENCODING)] #{literal(headers)} " \
    "BODY[TEXT]<0> #{literal(message[:body])})\r\n"
end

def expand_set(spec)
  spec.to_s.split(',').flat_map do |part|
    first, last = part.split(':')
    last.nil? ? [first.to_i] : (first.to_i..last.to_i).to_a
  end
end

server = TCPServer.new('127.0.0.1', PORT)
puts "imap stub listening on #{PORT} (no TLS)"
$stdout.flush

loop do
  socket = server.accept
  socket.print("* OK [CAPABILITY IMAP4REV1] smashboard imap stub ready\r\n")

  loop do
    line = socket.gets
    break if line.nil?

    line = line.strip
    tag, command, = line.split(' ', 3)
    upper = line.upcase

    case
    when upper.include?('CAPABILITY') && command.to_s.upcase == 'CAPABILITY'
      socket.print("* CAPABILITY IMAP4REV1\r\n#{tag} OK CAPABILITY completed\r\n")
    when command.to_s.upcase == 'LOGIN'
      socket.print("#{tag} OK LOGIN completed\r\n")
    when command.to_s.upcase == 'STATUS'
      mailbox = line[/STATUS\s+"?([^"\s]+)"?/i, 1]
      socket.print(%(* STATUS "#{mailbox}" (UNSEEN #{MAILBOX_UNSEEN})\r\n#{tag} OK STATUS completed\r\n))
    when command.to_s.upcase == 'EXAMINE'
      socket.print(
        "* FLAGS (\\Answered \\Flagged \\Deleted \\Seen \\Draft)\r\n" \
        "* #{MESSAGES.size} EXISTS\r\n* 0 RECENT\r\n" \
        "* OK [UIDVALIDITY 1] UIDs valid\r\n* OK [UIDNEXT 104] Predicted next UID\r\n" \
        "#{tag} OK [READ-ONLY] EXAMINE completed\r\n"
      )
    when upper.start_with?("#{tag.upcase} UID SEARCH")
      socket.print("* SEARCH #{MESSAGES.map { |m| m[:uid] }.join(' ')}\r\n#{tag} OK SEARCH completed\r\n")
    when upper.start_with?("#{tag.upcase} UID FETCH")
      # net-imap compresses a UID list into ranges, so [103,102,101] arrives
      # as "101:103". Both forms have to be expanded.
      requested = expand_set(line[/UID FETCH ([\d,:*]+)/i, 1])
      requested.each do |uid|
        message = MESSAGES.find { |m| m[:uid] == uid }
        socket.print(fetch_response(message)) if message
      end
      socket.print("#{tag} OK FETCH completed\r\n")
    when command.to_s.upcase == 'LOGOUT'
      socket.print("* BYE logging out\r\n#{tag} OK LOGOUT completed\r\n")
      break
    else
      socket.print("#{tag} OK completed\r\n")
    end
    $stdout.flush
  end

  socket.close
# A client that hangs up mid-session — a port probe, an aborted refresh — must
# not take the whole stub down with it.
rescue Errno::ECONNRESET, Errno::EPIPE, IOError => e
  warn "imap_stub: dropped connection (#{e.class})"
  begin
    socket&.close
  rescue IOError
    nil
  end
end
