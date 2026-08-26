# frozen_string_literal: true

# Breaking news from a configured feed (see Integrations::NewsFeed).
class NewsPanel < ApplicationPanel
  class << self
    def title = 'Breaking News'
    def description = 'The top developing story from a news feed you connect'
    def required_providers = %w[news_feed]
    def refresh_interval = 3.minutes
    def default_col_span = 2
  end

  def fetch
    source = connections.healthy.first || connections.first
    raise Integrations::Base::Error, 'no news feed connection configured' if source.nil?

    payload = Integrations::NewsFeed.new(source).breaking_news
    source.mark_synced!
    payload
  rescue Integrations::Base::Error => e
    source&.mark_failed!(e.message)
    raise
  end

  # A new top story is worth interrupting someone for; the same story on the
  # next refresh is not. Keyed on the headline rather than a timestamp so a
  # re-fetch of an unchanged story stays quiet.
  def notify(previous_data)
    story = cached_data[:story]
    return if story.blank? || story[:headline].blank?
    return if previous_data.dig(:story, :headline) == story[:headline]

    Notifications::Deliver.call(
      user,
      'breaking_news',
      Notifications::Deliver::Payload.new(
        title: 'Breaking',
        body: story[:headline],
        url: Array(story[:articles]).first&.dig(:link) || '/',
        tag: 'breaking-news',
        require_interaction: true
      ),
      dedupe_key: Digest::SHA256.hexdigest(story[:headline])
    )
  end
end
