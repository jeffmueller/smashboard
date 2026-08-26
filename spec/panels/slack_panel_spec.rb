# frozen_string_literal: true

require 'rails_helper'

RSpec.describe SlackPanel do
  let(:user) { create(:user) }
  let!(:work) { create(:connection, user: user, provider: 'slack', label: 'Work') }
  let(:panel) { user.panels.find_by!(kind: 'slack') }

  def counts(dms: 0, channel: 0, checked: 5, skipped: 0, top: [])
    { dm_unread: dms, channel_unread: channel, conversations_checked: checked,
      conversations_skipped: skipped, top: top }
  end

  def stub_slack(workspace: { team: 'Acme', url: 'https://acme.slack.com/' }, unread: counts)
    client = instance_double(Integrations::Slack, workspace: workspace, unread: unread)
    allow(Integrations::Slack).to receive(:new).and_return(client)
    client
  end

  it 'is no longer pending and needs a slack connection' do
    expect(described_class).not_to be_pending
    expect(described_class.required_providers).to eq(%w[slack])
  end

  it 'totals direct messages and channels' do
    stub_slack(unread: counts(dms: 4, channel: 9))

    payload = panel.presenter.fetch

    expect(payload[:total_unread]).to eq(13)
    expect(payload[:dm_unread]).to eq(4)
    expect(payload[:workspaces].first).to include(name: 'Acme', total_unread: 13)
  end

  it 'names the workspace from Slack, not the connection label' do
    stub_slack(workspace: { team: 'Acme Corp', url: 'https://acme.slack.com/' })

    expect(panel.presenter.fetch[:workspaces].first[:name]).to eq('Acme Corp')
  end

  it 'falls back to the connection label when Slack gives no team name' do
    stub_slack(workspace: { team: nil, url: nil })

    expect(panel.presenter.fetch[:workspaces].first[:name]).to eq('Work')
  end

  # Slack has no bulk unread endpoint, so a big workspace may not be fully
  # counted; the panel says so rather than presenting a short number as truth.
  it 'flags a count that could not cover the whole workspace' do
    stub_slack(unread: counts(dms: 2, channel: 3, checked: 40, skipped: 120))

    expect(panel.presenter.fetch[:incomplete]).to be(true)
  end

  it 'does not flag a complete count' do
    stub_slack(unread: counts(dms: 2, channel: 3, skipped: 0))

    expect(panel.presenter.fetch[:incomplete]).to be(false)
  end

  it 'passes the configured lookup budget through' do
    client = stub_slack
    panel.update!(settings: { 'lookup_budget' => 15 })

    panel.presenter.fetch

    expect(client).to have_received(:unread).with(budget: 15)
  end

  it 'clamps an absurd budget so one refresh cannot bury the rate limit' do
    client = stub_slack
    panel.update!(settings: { 'lookup_budget' => 5000 })

    panel.presenter.fetch

    expect(client).to have_received(:unread).with(budget: 200)
  end

  context 'with two workspaces' do
    let!(:personal) { create(:connection, user: user, provider: 'slack', label: 'Personal') }

    it 'sums across both, busiest first' do
      quiet = instance_double(Integrations::Slack, workspace: { team: 'Personal' }, unread: counts(dms: 1))
      busy = instance_double(Integrations::Slack, workspace: { team: 'Acme' }, unread: counts(dms: 4, channel: 20))
      allow(Integrations::Slack).to receive(:new).with(personal).and_return(quiet)
      allow(Integrations::Slack).to receive(:new).with(work).and_return(busy)

      payload = panel.presenter.fetch

      expect(payload[:total_unread]).to eq(25)
      expect(payload[:workspaces].pluck(:name)).to eq(%w[Acme Personal])
    end

    it 'keeps working when one workspace rejects its token' do
      healthy = instance_double(Integrations::Slack, workspace: { team: 'Acme' }, unread: counts(dms: 4))
      allow(Integrations::Slack).to receive(:new).with(work).and_return(healthy)
      allow(Integrations::Slack).to receive(:new).with(personal)
                                                 .and_raise(Integrations::Base::AuthenticationError, 'revoked')

      payload = panel.presenter.fetch

      expect(payload[:total_unread]).to eq(4)
      expect(payload[:partial]).to be(true)
      expect(personal.reload.status).to eq('error')
    end
  end

  it 'parks the panel in an error state when every workspace fails' do
    allow(Integrations::Slack).to receive(:new)
      .and_raise(Integrations::Base::RateLimited, 'rate limited')

    expect { panel.presenter.refresh! }.not_to raise_error
    expect(panel.reload.data_status).to eq('error')
  end
end
