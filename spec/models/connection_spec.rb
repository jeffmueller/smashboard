# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Connection do
  it { is_expected.to belong_to(:user) }

  it 'encrypts credentials at rest' do
    connection = create(:connection, credentials: { 'password' => 'hunter2' })

    raw = described_class.connection.select_value(
      described_class.sanitize_sql(['SELECT credentials FROM connections WHERE id = ?', connection.id])
    )

    expect(raw).not_to include('hunter2')
    expect(connection.reload.credential('password')).to eq('hunter2')
  end

  it 'keeps credentials out of JSON' do
    connection = create(:connection)

    expect(connection.as_json).not_to have_key('credentials')
  end

  it 'allows two accounts on the same provider with different labels' do
    user = create(:user)
    create(:connection, user: user, provider: 'imap', label: 'Gmail')

    expect(build(:connection, user: user, provider: 'imap', label: 'Fastmail')).to be_valid
    expect(build(:connection, user: user, provider: 'imap', label: 'Gmail')).not_to be_valid
  end

  describe '#mark_failed!' do
    let(:user) { create(:user) }
    let(:connection) { create(:connection, user: user, label: 'Fastmail') }

    before do
      create(:push_subscription, user: user)
      capture_pushes
    end

    it 'warns the user the first time an account breaks' do
      connection.mark_failed!('credentials rejected')

      expect(sent_pushes.size).to eq(1)
      expect(JSON.parse(sent_pushes.first[:message])['body']).to include('Fastmail', 'credentials rejected')
    end

    # A panel refreshing every few minutes against a dead server would otherwise
    # be a notification firehose.
    it 'stays quiet while the account is still broken' do
      3.times { connection.mark_failed!('credentials rejected') }

      expect(sent_pushes.size).to eq(1)
    end

    it 'warns again after the account recovers and breaks anew' do
      connection.mark_failed!('credentials rejected')
      connection.mark_synced!
      connection.mark_failed!('credentials rejected again')

      # Same day, so the daily dedupe key still suppresses the second warning.
      expect(sent_pushes.size).to eq(1)
      expect(connection.reload.status).to eq('error')
    end

    it 'records the error regardless of whether a notification went out' do
      connection.mark_failed!('server exploded')

      expect(connection.reload.last_error).to eq('server exploded')
      expect(connection.last_error_at).to be_present
    end

    # A blip at the far end is not something the user can do anything about, and
    # waking them for it is noise. The panel still shows the error.
    it 'stays quiet for a failure the user cannot act on' do
      connection.mark_failed!('Google was unreachable', actionable: false)

      expect(sent_pushes).to be_empty
      expect(connection.reload.status).to eq('error')
    end

    it 'points an OAuth connection straight at signing in again' do
      oauth = create(:connection, user: user, provider: 'google_calendar', label: 'Work calendar')

      oauth.mark_failed!('Google access needs granting again')

      message = JSON.parse(sent_pushes.first[:message])
      expect(message['url']).to eq("/oauth/google?connection_id=#{oauth.id}&provider=google_calendar")
      expect(message['body']).to include('sign in again')
    end

    it 'points everything else at the connections page' do
      connection.mark_failed!('credentials rejected')

      expect(JSON.parse(sent_pushes.first[:message])['url']).to eq('/connections')
    end
  end
end
