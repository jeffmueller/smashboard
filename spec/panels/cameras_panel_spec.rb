# frozen_string_literal: true

require 'rails_helper'

RSpec.describe CamerasPanel do
  let(:user) { create(:user) }
  let!(:house) { create(:connection, user: user, provider: 'home_assistant', label: 'House') }
  let(:panel) { user.panels.find_by!(kind: 'cameras') }

  def camera(entity_id, name:, state: 'idle', available: true)
    { entity_id: entity_id, name: name, state: state, available: available,
      updated_at: '2026-08-25T22:00:00+00:00' }
  end

  def stub_home_assistant(cameras)
    allow(Integrations::HomeAssistant).to receive(:new)
      .and_return(instance_double(Integrations::HomeAssistant, cameras: cameras))
  end

  it 'is no longer pending and needs a Home Assistant connection' do
    expect(described_class).not_to be_pending
    expect(described_class.required_providers).to eq(%w[home_assistant])
  end

  it 'tags each camera with the connection its frames come from' do
    stub_home_assistant([camera('camera.front_door', name: 'Front Door')])

    entry = panel.presenter.fetch[:cameras].first

    expect(entry).to include(entity_id: 'camera.front_door', name: 'Front Door')
    expect(entry[:connection_id]).to eq(house.id)
  end

  it 'carries the snapshot interval so the browser knows how often to pull' do
    stub_home_assistant([])

    expect(panel.presenter.fetch[:refresh_seconds]).to eq(described_class::DEFAULT_REFRESH_SECONDS)
  end

  it 'honours a configured interval' do
    stub_home_assistant([])
    panel.update!(settings: { 'refresh_seconds' => 10 })

    expect(panel.presenter.fetch[:refresh_seconds]).to eq(10)
  end

  # Nothing should be able to make the browser hammer a Raspberry Pi.
  it 'clamps an absurd interval' do
    stub_home_assistant([])
    panel.update!(settings: { 'refresh_seconds' => 0 })

    expect(panel.presenter.fetch[:refresh_seconds]).to eq(5)
  end

  it 'passes an unavailable camera through so the view can say so' do
    stub_home_assistant([camera('camera.side_gate', name: 'Side Gate',
                                                    state: 'unavailable', available: false)])

    expect(panel.presenter.fetch[:cameras].first[:available]).to be(false)
  end

  context 'with two Home Assistant instances' do
    let!(:cabin) { create(:connection, user: user, provider: 'home_assistant', label: 'Cabin') }

    let(:at_house) do
      instance_double(Integrations::HomeAssistant,
                      cameras: [camera('camera.front_door', name: 'Front Door')])
    end

    it 'merges cameras from both' do
      at_cabin = instance_double(Integrations::HomeAssistant,
                                 cameras: [camera('camera.porch', name: 'Porch')])
      allow(Integrations::HomeAssistant).to receive(:new).with(house).and_return(at_house)
      allow(Integrations::HomeAssistant).to receive(:new).with(cabin).and_return(at_cabin)

      expect(panel.presenter.fetch[:cameras].pluck(:name)).to contain_exactly('Front Door', 'Porch')
    end

    it 'keeps working when one instance is unreachable' do
      allow(Integrations::HomeAssistant).to receive(:new).with(house).and_return(at_house)
      allow(Integrations::HomeAssistant).to receive(:new).with(cabin)
                                                         .and_raise(Integrations::Base::Unavailable, 'offline')

      payload = panel.presenter.fetch

      expect(payload[:cameras].size).to eq(1)
      expect(payload[:partial]).to be(true)
      expect(cabin.reload.status).to eq('error')
    end
  end

  it 'parks the panel in an error state when Home Assistant is down' do
    allow(Integrations::HomeAssistant).to receive(:new)
      .and_raise(Integrations::Base::Unavailable, 'HA down')

    expect { panel.presenter.refresh! }.not_to raise_error
    expect(panel.reload.data_status).to eq('error')
  end
end
