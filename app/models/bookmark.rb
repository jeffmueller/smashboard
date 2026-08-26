# frozen_string_literal: true

# A link on the dashboard. Local data — no integration, nothing fetched.
class Bookmark < ApplicationRecord
  include Positioned

  # `javascript:` and `data:` URLs in an href execute when clicked, so the
  # scheme is allow-listed rather than merely parsed.
  ALLOWED_SCHEMES = %w[http https].freeze

  # A scheme is everything before the first colon — except that "localhost:3000"
  # is a host and a port, so a colon followed by a digit doesn't count as one.
  SCHEME = /\A[a-z][a-z0-9+.-]*:(?!\d)/i

  belongs_to :user

  validates :title, presence: true, length: { maximum: 80 }
  validates :url, presence: true, length: { maximum: 2000 }
  validate :url_is_a_web_address

  before_validation :normalize_url
  before_validation :fill_in_title

  # "github.com" is what people type; a bare host is not a valid href.
  #
  # Only a string with no scheme at all gets one prepended. Matching on
  # "scheme://" instead would treat `javascript:alert(1)` as scheme-less and
  # rewrite it to `https://javascript:alert(1)`, hiding the dangerous scheme
  # from the allow-list below rather than tripping it.
  def normalize_url
    return if url.blank?

    # Control characters never belong in a URL, and browsers strip some of them
    # when resolving an href — `java\tscript:` is the classic bypass.
    self.url = url.strip.gsub(/[[:cntrl:]]/, '')
    self.url = "https://#{url}" unless url.match?(SCHEME)
  end

  # What to show when the bookmark has no emoji: the first character of the
  # title, which needs no network request and themes correctly.
  def initial
    title.to_s.strip.first.to_s.upcase.presence || '?'
  end

  # The bit of the URL worth showing under the title. The port is kept when it
  # isn't the scheme's default, because "homeassistant.local:8123" and
  # "homeassistant.local" are different machines on a home network.
  def host
    parsed = URI.parse(url)
    name = parsed.host.to_s.delete_prefix('www.').presence
    return nil if name.nil?

    parsed.port == parsed.default_port ? name : "#{name}:#{parsed.port}"
  rescue URI::Error
    nil
  end

  private

  def fill_in_title
    return if title.present? || url.blank?

    self.title = host.presence || url
  end

  def url_is_a_web_address
    return if url.blank?

    parsed = URI.parse(url)
    return errors.add(:url, 'must be a web address') unless ALLOWED_SCHEMES.include?(parsed.scheme)

    errors.add(:url, 'needs a host') if parsed.host.blank?
  rescue URI::Error
    errors.add(:url, "doesn't look like a web address")
  end
end
