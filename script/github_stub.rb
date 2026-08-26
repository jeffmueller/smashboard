# A throwaway GitHub API for developing the GitHub panels without a real token.
#
#   ruby script/github_stub.rb        # listens on 127.0.0.1:4311
#
# Then add a `github` connection with api_endpoint http://127.0.0.1:4311/ and
# any access token. It serves /user, /notifications and /search/issues with
# enough shape for the real octokit client to parse.
require 'socket'
require 'json'
require 'cgi'

PORT = 4311
LOGIN = 'octocat'

def notifications
  [
    { id: '1', reason: 'review_requested', unread: true, updated_at: '2026-08-25T17:40:00Z',
      subject: { title: 'Extract the panel refresh scheduler', type: 'PullRequest',
                 url: 'https://api.github.com/repos/octocat/smashboard/pulls/42' },
      repository: { full_name: 'octocat/smashboard', html_url: 'https://github.com/octocat/smashboard' } },
    { id: '2', reason: 'mention', unread: true, updated_at: '2026-08-25T16:10:00Z',
      subject: { title: 'Countdown dismissal drops the wrong occurrence', type: 'Issue',
                 url: 'https://api.github.com/repos/octocat/smashboard/issues/40' },
      repository: { full_name: 'octocat/smashboard', html_url: 'https://github.com/octocat/smashboard' } },
    { id: '3', reason: 'ci_activity', unread: true, updated_at: '2026-08-25T15:05:00Z',
      subject: { title: 'CI failed on main', type: 'CheckSuite', url: nil },
      repository: { full_name: 'octocat/quartz', html_url: 'https://github.com/octocat/quartz' } },
    { id: '4', reason: 'author', unread: true, updated_at: '2026-08-25T11:20:00Z',
      subject: { title: 'v2.1.0', type: 'Release',
                 url: 'https://api.github.com/repos/octocat/newsroom/releases/99' },
      repository: { full_name: 'octocat/newsroom', html_url: 'https://github.com/octocat/newsroom' } }
  ]
end

def review_requested
  [
    { id: 101, number: 42, title: 'Extract the panel refresh scheduler',
      html_url: 'https://github.com/octocat/smashboard/pull/42',
      repository_url: 'https://api.github.com/repos/octocat/smashboard',
      user: { login: 'dana' }, comments: 4, draft: false, updated_at: '2026-08-25T17:40:00Z' },
    { id: 102, number: 17, title: 'Bump Rails to 8.1.3',
      html_url: 'https://github.com/octocat/quartz/pull/17',
      repository_url: 'https://api.github.com/repos/octocat/quartz',
      user: { login: 'sam' }, comments: 0, draft: false, updated_at: '2026-08-25T14:02:00Z' }
  ]
end

def authored
  [
    { id: 201, number: 43, title: 'Add the GitHub panels',
      html_url: 'https://github.com/octocat/smashboard/pull/43',
      repository_url: 'https://api.github.com/repos/octocat/smashboard',
      user: { login: LOGIN }, comments: 1, draft: true, updated_at: '2026-08-25T18:00:00Z' },
    { id: 202, number: 9, title: 'Fix the RSS parser on empty feeds',
      html_url: 'https://github.com/octocat/newsroom/pull/9',
      repository_url: 'https://api.github.com/repos/octocat/newsroom',
      user: { login: LOGIN }, comments: 6, draft: false, updated_at: '2026-08-24T09:15:00Z' }
  ]
end

server = TCPServer.new('127.0.0.1', PORT)
puts "github stub listening on #{PORT}"
$stdout.flush

loop do
  client = server.accept
  request_line = client.gets
  # A bare TCP connect with no request line — a port probe, a browser
  # preconnect — must close that one connection, not end the server.
  next client.close if request_line.nil?

  _method, target, = request_line.split
  next client.close if target.nil?
  while (line = client.gets) && line != "\r\n"
    # headers are irrelevant here
  end

  path, query = target.split('?', 2)
  query = CGI.unescape(query.to_s)

  payload =
    case path
    when '/user' then { login: LOGIN }
    when '/notifications' then notifications
    when '/search/issues'
      { total_count: 2, incomplete_results: false,
        items: query.include?('review-requested') ? review_requested : authored }
    else {}
    end

  body = JSON.generate(payload)
  client.print("HTTP/1.1 200 OK\r\nContent-Type: application/json; charset=utf-8\r\nContent-Length: #{body.bytesize}\r\nConnection: close\r\n\r\n#{body}")
  client.close
end
