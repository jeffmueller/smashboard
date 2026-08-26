# frozen_string_literal: true

module ImapHelpers
  # A stand-in for a live Net::IMAP session. Real net-imap response structs are
  # used so the client is exercised against the shapes it will actually meet.
  def fake_imap(unseen: 0, uids: [], messages: [])
    imap = instance_double(Net::IMAP, disconnected?: false)

    allow(Net::IMAP).to receive(:new).and_return(imap)
    allow(imap).to receive(:login)
    allow(imap).to receive(:logout)
    allow(imap).to receive(:disconnect)
    allow(imap).to receive(:examine)
    allow(imap).to receive(:select)
    allow(imap).to receive_messages(status: { 'UNSEEN' => unseen }, uid_search: uids, uid_fetch: messages)

    imap
  end

  def imap_message(uid:, from_name: 'Dana Lee', from: 'dana@example.com', subject: 'Standup notes',
                   message_id: nil, received_at: Time.utc(2026, 8, 25, 13, 30),
                   content_type: 'text/plain; charset=UTF-8', encoding: nil, body: 'Body text here.')
    mailbox, host = from.split('@')
    address = Net::IMAP::Address.new(from_name, nil, mailbox, host)
    envelope = Net::IMAP::Envelope.new(received_at.rfc2822, subject, [address], nil, nil, nil, nil, nil,
                                       nil, message_id || "<#{uid}@example.com>")

    headers = "Content-Type: #{content_type}\r\n"
    headers << "Content-Transfer-Encoding: #{encoding}\r\n" if encoding

    Net::IMAP::FetchData.new(uid, {
                               'UID' => uid,
                               'ENVELOPE' => envelope,
                               'INTERNALDATE' => received_at,
                               'BODY[HEADER.FIELDS (CONTENT-TYPE CONTENT-TRANSFER-ENCODING)]' => headers,
                               'BODY[TEXT]<0>' => body
                             })
  end
end

RSpec.configure { |config| config.include ImapHelpers }
