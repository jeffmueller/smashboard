# frozen_string_literal: true

require 'rails_helper'

RSpec.describe NewsPanel do
  let(:user) { create(:user) }
  let(:panel) { create(:panel, user: user, kind: 'news') }
  let!(:connection) { create(:connection, user: user, provider: 'news_feed') }

  let(:body) do
    {
      headline: 'Something happened',
      summary: 'A summary of the thing.',
      mentionCount: 9,
      sources: %w[Reuters AP],
      articles: [{ source: 'Reuters', title: 'The thing', link: 'https://example.com/a' }]
    }
  end

  def stub_breaking_news(status: 200, response: body)
    stub_request(:get, 'https://news.example.com/api/breaking-news')
      .to_return(status: status, body: response.to_json, headers: { 'Content-Type' => 'application/json' })
  end

  it 'caches the fetched story and marks the connection healthy' do
    stub_breaking_news

    panel.presenter.refresh!

    expect(panel.reload.data_status).to eq('ok')
    expect(panel.data.dig('story', 'headline')).to eq('Something happened')
    expect(panel.data.dig('story', 'mention_count')).to eq(9)
    expect(connection.reload.status).to eq('ok')
  end

  it 'authenticates with the shared password cookie' do
    request = stub_breaking_news

    panel.presenter.refresh!

    expect(request.with(headers: { 'Cookie' => 'auth=hunter2' })).to have_been_made
  end

  # The cookie name belongs to whichever feed is being read, not to this app, so
  # it is a per-connection setting. Without this the escape hatch that lets an
  # existing feed keep its own cookie name goes untested.
  it 'sends the password in whatever cookie the feed names' do
    connection.update!(settings: { 'base_url' => 'https://news.example.com', 'cookie_name' => 'session' })
    request = stub_breaking_news

    panel.presenter.refresh!

    expect(request.with(headers: { 'Cookie' => 'session=hunter2' })).to have_been_made
  end

  it 'parks the panel when no feed URL is configured' do
    connection.update!(settings: {})

    expect { panel.presenter.refresh! }.not_to raise_error

    expect(panel.reload.data_status).to eq('error')
    expect(panel.last_error).to include('no news feed URL configured')
  end

  it 'parks the panel in an error state rather than raising' do
    stub_breaking_news(status: 401, response: { error: 'unauthorized' })

    expect { panel.presenter.refresh! }.not_to raise_error

    expect(panel.reload.data_status).to eq('error')
    expect(connection.reload.status).to eq('error')
  end

  # faraday-retry raises rather than returning once it has spent its attempts on
  # a retryable status; that must still surface as an Integrations error.
  it 'turns an exhausted retry into a panel error, not a Faraday exception' do
    stub_breaking_news(status: 503, response: { error: 'unavailable' })

    expect { panel.presenter.refresh! }.not_to raise_error
    expect(panel.reload.data_status).to eq('error')
    expect(panel.last_error).to include('Integrations::')
  end

  it 'reports itself unconfigured with no connection' do
    connection.destroy

    expect(panel.reload.presenter).not_to be_configured
  end

  describe 'breaking news alerts' do
    let!(:device) { create(:push_subscription, user: user) }

    before { capture_pushes }

    it 'raises an alarm the first time a headline appears' do
      stub_breaking_news

      panel.presenter.refresh!

      expect(sent_pushes.size).to eq(1)
      expect(JSON.parse(sent_pushes.first[:message]))
        .to include('title' => 'Breaking', 'body' => 'Something happened')
    end

    it 'stays quiet when a refresh returns the same headline' do
      stub_breaking_news

      3.times { panel.presenter.refresh! }

      expect(sent_pushes.size).to eq(1)
    end

    it 'raises a new alarm when the story changes' do
      stub_breaking_news
      panel.presenter.refresh!

      stub_breaking_news(response: body.merge(headline: 'Something else happened'))
      panel.presenter.refresh!

      expect(sent_pushes.size).to eq(2)
    end

    it 'links the notification at the first source article' do
      stub_breaking_news

      panel.presenter.refresh!

      expect(JSON.parse(sent_pushes.first[:message])['url']).to eq('https://example.com/a')
    end

    it 'does not let a notification failure fail the refresh' do
      stub_breaking_news
      allow(Notifications::Deliver).to receive(:call).and_raise(StandardError, 'boom')

      expect { panel.presenter.refresh! }.not_to raise_error
      expect(panel.reload.data_status).to eq('ok')
    end
  end
end
