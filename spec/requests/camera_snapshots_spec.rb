# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Camera snapshots' do
  let(:user) { create(:user) }
  let!(:connection) do
    create(:connection, user: user, provider: 'home_assistant', label: 'House',
                        settings: { 'base_url' => 'http://homeassistant.local:8123' },
                        credentials: { 'access_token' => 'llat-secret' })
  end

  def stub_frame(entity_id = 'camera.front_door', status: 200)
    stub_request(:get, "http://homeassistant.local:8123/api/camera_proxy/#{entity_id}")
      .to_return(status: status, body: 'JPEGBYTES', headers: { 'Content-Type' => 'image/jpeg' })
  end

  def snapshot_path(entity_id = 'camera.front_door', connection_id: connection.id)
    camera_snapshot_path(connection_id: connection_id, entity_id: entity_id)
  end

  it 'requires a signed-in user' do
    get snapshot_path

    expect(response).to redirect_to(new_user_session_path)
  end

  context 'when signed in' do
    before { sign_in user }

    it 'returns the frame as an image' do
      stub_frame

      get snapshot_path

      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq('image/jpeg')
      expect(response.body).to eq('JPEGBYTES')
    end

    # Frames are per-viewer and immediately stale.
    it 'forbids caching' do
      stub_frame

      get snapshot_path

      expect(response.headers['Cache-Control']).to include('no-store')
    end

    # The long-lived token must never reach the browser.
    it 'never exposes the Home Assistant token' do
      stub_frame

      get snapshot_path

      expect(response.body).not_to include('llat-secret')
      expect(response.headers.to_h.values.join).not_to include('llat-secret')
    end

    it "cannot use another account's Home Assistant" do
      theirs = create(:connection, user: create(:user), provider: 'home_assistant',
                                   settings: { 'base_url' => 'http://elsewhere.local:8123' },
                                   credentials: { 'access_token' => 'not-yours' })

      get snapshot_path('camera.front_door', connection_id: theirs.id)

      expect(response).to have_http_status(:not_found)
      expect(a_request(:get, /elsewhere\.local/)).not_to have_been_made
    end

    it 'reports a dead camera as a bad gateway rather than raising' do
      stub_frame(status: 500)

      get snapshot_path

      expect(response).to have_http_status(:bad_gateway)
    end

    describe 'the entity id is the only thing between a URL and arbitrary HA endpoints' do
      it 'does not route a non-camera entity' do
        get "/cameras/#{connection.id}/sensor.temperature/snapshot"

        expect(response).to have_http_status(:not_found)
        expect(a_request(:get, /homeassistant\.local/)).not_to have_been_made
      end

      it 'does not route a traversal attempt' do
        get "/cameras/#{connection.id}/camera.a%2F..%2F..%2Fapi%2Fconfig/snapshot"

        expect(response).to have_http_status(:not_found)
        expect(a_request(:get, /homeassistant\.local/)).not_to have_been_made
      end

      it 'does not route an uppercase or spaced entity id' do
        get "/cameras/#{connection.id}/camera.Front%20Door/snapshot"

        expect(response).to have_http_status(:not_found)
        expect(a_request(:get, /homeassistant\.local/)).not_to have_been_made
      end

      it 'keeps the dot in the entity id rather than reading it as a format' do
        stub_frame('camera.back_yard')

        get snapshot_path('camera.back_yard')

        expect(response).to have_http_status(:ok)
        expect(a_request(:get, %r{/api/camera_proxy/camera\.back_yard})).to have_been_made
      end
    end
  end
end
