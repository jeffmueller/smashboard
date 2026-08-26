# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Integrations::NewsFeed do
  let(:connection) do
    create(:connection, provider: 'news_feed', label: 'Newsroom',
                        settings: { 'base_url' => 'https://news.example.com' },
                        credentials: { 'password' => 'hunter2' })
  end

  let(:client) { described_class.new(connection) }

  let(:body) do
    {
      headline: 'Something happened',
      summary: 'A summary of the thing.',
      mentionCount: 9,
      sources: %w[Reuters AP],
      articles: [{ source: 'Reuters', title: 'The thing', link: 'https://example.com/a' }]
    }
  end

  def stub_feed(url: 'https://news.example.com/api/breaking-news', status: 200, response: body)
    stub_request(:get, url)
      .to_return(status: status, body: response.to_json, headers: { 'Content-Type' => 'application/json' })
  end

  describe '#breaking_news' do
    it 'normalizes the feed camelCase into the shape the panel renders' do
      stub_feed

      story = client.breaking_news[:story]

      expect(story).to include(
        headline: 'Something happened',
        summary: 'A summary of the thing.',
        mention_count: 9,
        sources: %w[Reuters AP]
      )
      expect(story[:articles]).to eq([{ source: 'Reuters', title: 'The thing', link: 'https://example.com/a' }])
    end

    it 'reports no story rather than failing when the feed has nothing' do
      stub_feed(response: {})

      expect(client.breaking_news[:story]).to be_nil
    end
  end

  describe 'the password cookie' do
    it 'defaults to a neutral name' do
      request = stub_feed

      client.breaking_news

      expect(request.with(headers: { 'Cookie' => "#{described_class::DEFAULT_AUTH_COOKIE}=hunter2" }))
        .to have_been_made
    end

    # The name is the remote server's choice, so it has to be configurable
    # without a code change here.
    it 'uses the cookie the connection names' do
      connection.update!(settings: connection.settings.merge('cookie_name' => 'session'))
      request = stub_feed

      client.breaking_news

      expect(request.with(headers: { 'Cookie' => 'session=hunter2' })).to have_been_made
    end

    it 'sends no cookie at all for a feed that needs no password' do
      connection.update!(credentials: {})
      request = stub_feed

      client.breaking_news

      expect(request.with { |req| !req.headers.key?('Cookie') }).to have_been_made
    end
  end

  describe 'the feed URL' do
    it 'falls back to the environment when the connection leaves it blank' do
      connection.update!(settings: {})
      request = stub_feed(url: 'https://fallback.example.com/api/breaking-news')

      allow(ENV).to receive(:fetch).and_call_original
      allow(ENV).to receive(:fetch).with('NEWS_FEED_BASE_URL', nil).and_return('https://fallback.example.com')

      client.breaking_news

      expect(request).to have_been_made
    end

    # There is no sensible host to guess for a feed somebody else runs, so this
    # is an error rather than a default.
    it 'raises Unavailable when there is no URL anywhere' do
      connection.update!(settings: {})

      expect { client.breaking_news }
        .to raise_error(Integrations::Base::Unavailable, /no news feed URL configured/)
    end
  end
end
