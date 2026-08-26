# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Integrations::HomeAssistant do
  let(:connection) do
    create(:connection, provider: 'home_assistant', label: 'House',
                        settings: { 'base_url' => 'http://homeassistant.local:8123' },
                        credentials: { 'access_token' => 'llat-secret' })
  end

  let(:client) { described_class.new(connection) }

  def json(body, status: 200)
    { status: status, body: body.to_json, headers: { 'Content-Type' => 'application/json' } }
  end

  def camera_state(entity_id, name:, state: 'idle')
    { entity_id: entity_id, state: state, last_updated: '2026-08-25T22:00:00+00:00',
      attributes: { friendly_name: name } }
  end

  def stub_states(*states)
    stub_request(:get, 'http://homeassistant.local:8123/api/states')
      .to_return(json(states))
  end

  describe '#cameras' do
    it 'authenticates with the long-lived token' do
      request = stub_states
      request.with(headers: { 'Authorization' => 'Bearer llat-secret' })

      client.cameras

      expect(a_request(:get, %r{/api/states}).with(headers: { 'Authorization' => 'Bearer llat-secret' }))
        .to have_been_made
    end

    it 'keeps only camera entities' do
      stub_states(camera_state('camera.front_door', name: 'Front Door'),
                  { entity_id: 'sensor.temperature', state: '21', attributes: {} },
                  { entity_id: 'light.kitchen', state: 'on', attributes: {} })

      expect(client.cameras.pluck(:entity_id)).to eq(['camera.front_door'])
    end

    it 'normalises a camera' do
      stub_states(camera_state('camera.front_door', name: 'Front Door', state: 'recording'))

      expect(client.cameras.first).to include(
        entity_id: 'camera.front_door', name: 'Front Door',
        state: 'recording', available: true
      )
    end

    it 'falls back to the entity id when HA has no friendly name' do
      stub_states({ entity_id: 'camera.side_gate', state: 'idle', attributes: {} })

      expect(client.cameras.first[:name]).to eq('Side gate')
    end

    it 'marks an unavailable camera' do
      stub_states(camera_state('camera.front_door', name: 'Front Door', state: 'unavailable'))

      expect(client.cameras.first[:available]).to be(false)
    end

    it 'returns every camera when no selection is configured' do
      stub_states(camera_state('camera.a', name: 'A'), camera_state('camera.b', name: 'B'))

      expect(client.cameras.size).to eq(2)
    end

    it 'honours a chosen subset, in the order given' do
      connection.update!(settings: connection.settings.merge('entity_ids' => 'camera.b, camera.a'))
      stub_states(camera_state('camera.a', name: 'A'),
                  camera_state('camera.b', name: 'B'),
                  camera_state('camera.c', name: 'C'))

      expect(client.cameras.pluck(:entity_id)).to eq(['camera.b', 'camera.a'])
    end
  end

  describe '#snapshot' do
    it 'returns the frame and its content type' do
      stub_request(:get, 'http://homeassistant.local:8123/api/camera_proxy/camera.front_door')
        .to_return(status: 200, body: 'JPEGBYTES', headers: { 'Content-Type' => 'image/jpeg' })

      snapshot = client.snapshot('camera.front_door')

      expect(snapshot.body).to eq('JPEGBYTES')
      expect(snapshot.content_type).to eq('image/jpeg')
    end

    # This regex is the only thing between a URL parameter and an arbitrary
    # Home Assistant endpoint.
    ['sensor.temperature', 'camera.front_door/../../api/config', '../api/config',
     'camera.Front_Door', 'camera.front door', ''].each do |entity_id|
      it "refuses to proxy #{entity_id.inspect}" do
        expect { client.snapshot(entity_id) }.to raise_error(ArgumentError, /not a camera entity/)
        expect(a_request(:get, /camera_proxy/)).not_to have_been_made
      end
    end

    it 'raises Unavailable when the camera will not answer' do
      stub_request(:get, %r{/api/camera_proxy/camera\.front_door}).to_return(status: 500, body: '')

      expect { client.snapshot('camera.front_door') }.to raise_error(Integrations::Base::Unavailable)
    end
  end

  describe 'configuration and failures' do
    it 'keeps a path when the instance is behind a reverse proxy' do
      connection.update!(settings: { 'base_url' => 'https://home.example.com/hass' })
      request = stub_request(:get, 'https://home.example.com/hass/api/states').to_return(json([]))

      client.cameras

      expect(request).to have_been_made
    end

    it 'refuses to run without a URL' do
      connection.update!(settings: {})

      expect { client.cameras }.to raise_error(Integrations::Base::Unavailable, /no Home Assistant URL/)
    end

    it 'refuses to run without a token' do
      connection.update!(credentials: {})

      expect { client.cameras }.to raise_error(Integrations::Base::AuthenticationError, /no Home Assistant token/)
    end

    it 'reports a rejected token' do
      stub_request(:get, %r{/api/states}).to_return(status: 401, body: '{}')

      expect { client.cameras }.to raise_error(Integrations::Base::AuthenticationError)
    end

    it 'reports an unreachable instance as unavailable' do
      stub_request(:get, %r{/api/states}).to_return(status: 503, body: '{}')

      expect { client.cameras }.to raise_error(Integrations::Base::Unavailable)
    end
  end
end
