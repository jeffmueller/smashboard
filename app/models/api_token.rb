# frozen_string_literal: true

# Bearer credential for the JSON API, so a native client can authenticate
# without a session cookie. Only the digest is persisted — the plaintext is
# returned once, at creation, and never recoverable afterwards.
class ApiToken < ApplicationRecord
  TOKEN_BYTES = 32

  belongs_to :user

  attr_reader :plaintext_token

  validates :name, presence: true, length: { maximum: 120 }
  validates :token_digest, presence: true, uniqueness: true

  scope :active, lambda {
    where(revoked_at: nil).where(expires_at: nil).or(where(revoked_at: nil).where(expires_at: Time.current..))
  }

  before_validation :assign_token, on: :create

  def self.digest(token)
    OpenSSL::Digest::SHA256.hexdigest(token)
  end

  def self.authenticate(token)
    return nil if token.blank?

    active.find_by(token_digest: digest(token))
  end

  def revoke!
    update!(revoked_at: Time.current)
  end

  def revoked?
    revoked_at.present?
  end

  def expired?
    expires_at.present? && expires_at < Time.current
  end

  # Deliberately skips validations and callbacks: this fires on every
  # authenticated API request and must not be able to fail the request.
  def touch_usage!
    update_column(:last_used_at, Time.current) # rubocop:disable Rails/SkipsModelValidations
  end

  private

  def assign_token
    return if token_digest.present?

    @plaintext_token = "smb_#{SecureRandom.urlsafe_base64(TOKEN_BYTES)}"
    self.token_digest = self.class.digest(@plaintext_token)
  end
end
