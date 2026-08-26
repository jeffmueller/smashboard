# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Countdowns' do
  let(:user) { create(:user) }
  let(:headers) { api_headers_for(user) }

  describe 'POST /api/v1/countdowns/:id/dismiss' do
    it 'skips the given occurrence and returns the next one' do
      countdown = create(:countdown, :recurring, user: user)
      first = countdown.next_occurrence_at

      post "/api/v1/countdowns/#{countdown.id}/dismiss",
           params: { occurrence_at: first.iso8601 }, headers: headers, as: :json

      expect(response).to have_http_status(:ok)
      expect(Time.iso8601(response.parsed_body['occurrence_at'])).to be > first
    end

    it 'rejects a malformed timestamp' do
      countdown = create(:countdown, :recurring, user: user)

      post "/api/v1/countdowns/#{countdown.id}/dismiss",
           params: { occurrence_at: 'yesterday' }, headers: headers, as: :json

      expect(response).to have_http_status(:bad_request)
    end

    it 'cannot touch another user\'s countdown' do
      countdown = create(:countdown, :recurring, user: create(:user))

      post "/api/v1/countdowns/#{countdown.id}/dismiss",
           params: { occurrence_at: Time.current.iso8601 }, headers: headers, as: :json

      expect(response).to have_http_status(:not_found)
    end
  end

  describe 'POST /api/v1/countdowns' do
    it 'creates a recurring countdown' do
      post '/api/v1/countdowns',
           params: { countdown: { name: 'School run', rrule: 'FREQ=DAILY', occurs_at_time: '15:10',
                                  starts_on: Date.current.iso8601 } },
           headers: headers, as: :json

      expect(response).to have_http_status(:created)
      expect(response.parsed_body['recurring']).to be(true)
    end

    it 'reports validation failures' do
      post '/api/v1/countdowns', params: { countdown: { name: 'Nothing' } }, headers: headers, as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body['error']).to be_present
    end
  end
end
