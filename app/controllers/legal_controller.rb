# frozen_string_literal: true

# The privacy policy and terms.
#
# Public by design: Google's OAuth consent screen requires both to be reachable
# without signing in, and a reviewer checks them from a signed-out browser.
class LegalController < ApplicationController
  skip_before_action :authenticate_user!

  # These are the only pages a signed-out visitor can read, and they have
  # nothing to do with signing in, so they get the plain dashboard chrome
  # rather than the centred auth card.
  layout 'legal'

  def privacy; end
  def terms; end
end
