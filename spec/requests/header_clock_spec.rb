# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'The top bar clock' do
  let(:user) { create(:user, time_zone: 'Pacific Time (US & Canada)') }

  it 'renders the time and date centred in the bar when signed in' do
    sign_in user
    get root_path

    expect(response.body).to include('data-controller="clock"')
    expect(response.body).to include('data-clock-time-zone-value="Pacific Time (US &amp; Canada)"')
    expect(response.body).to include('justify-self-center')
  end

  it 'renders it in the user zone rather than the server one' do
    sign_in user
    # 02:30 UTC is 19:30 the previous day in Pacific, so this fails loudly if the
    # bar ever starts reading the server's clock instead of the user's.
    travel_to(Time.utc(2026, 8, 28, 2, 30, 0)) do
      get root_path
      expect(response.body).to include('7:30 PM')
      expect(response.body).to include('Thursday, August 27, 2026')
    end
  end

  it 'shows no clock to a signed-out visitor' do
    get privacy_path

    expect(response.body).not_to include('data-controller="clock"')
  end
end
