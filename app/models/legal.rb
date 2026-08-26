# frozen_string_literal: true

# Facts the privacy policy and terms need, in one place so the two documents
# can't drift from each other or from the deployment.
module Legal
  SERVICE_NAME = 'smashboard'

  # Bumped by hand when the wording changes, not derived from the file — the
  # date on a policy is a claim about when the terms last changed, and a deploy
  # that touches nothing substantive shouldn't restate it.
  LAST_UPDATED = Date.new(2026, 8, 26)

  class << self
    # The host this instance is served under, which is what a reader is
    # actually agreeing about.
    def host
      ENV.fetch('APP_HOST', 'this installation')
    end

    # Whoever runs this instance. Self-hosted software has no vendor to point
    # at, so the operator is the data controller and the only useful contact.
    def contact
      ENV.fetch('LEGAL_CONTACT_EMAIL', nil).presence
    end
  end
end
