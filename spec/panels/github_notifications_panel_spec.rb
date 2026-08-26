# frozen_string_literal: true

require 'rails_helper'

RSpec.describe GithubNotificationsPanel do
  let(:user) { create(:user) }
  let!(:work) { create(:connection, user: user, provider: 'github', label: 'Work') }
  let(:panel) { user.panels.find_by!(kind: 'github_notifications') }

  it 'is no longer pending and needs a github connection' do
    expect(described_class).not_to be_pending
    expect(described_class.required_providers).to eq(%w[github])
  end

  it 'counts everything unread but only lists up to the limit' do
    stub_github(notifications: (1..12).map { |i| github_notification(i, "2026-08-25T12:#{format('%02d', i)}:00Z") })
    panel.update!(settings: { 'limit' => 5 })

    payload = panel.presenter.fetch

    expect(payload[:unread_count]).to eq(12)
    expect(payload[:notifications].size).to eq(5)
  end

  it 'lists the most recently updated first' do
    stub_github(notifications: [github_notification(1, '2026-08-25T09:00:00Z'),
                                github_notification(2, '2026-08-25T15:00:00Z')])

    expect(panel.presenter.fetch[:notifications].pluck(:id)).to eq([2, 1])
  end

  # A full page back means the true count is unknown, so the UI says "50+".
  it 'flags when a whole page came back' do
    page = Array.new(Integrations::Github::PAGE_SIZE) { |i| github_notification(i, '2026-08-25T12:00:00Z') }
    stub_github(notifications: page)

    expect(panel.presenter.fetch[:capped]).to be(true)
  end

  it 'merges accounts and survives one of them failing' do
    personal = create(:connection, user: user, provider: 'github', label: 'Personal')
    healthy = instance_double(Integrations::Github,
                              notifications: [github_notification(1, '2026-08-25T12:00:00Z')])

    allow(Integrations::Github).to receive(:new).with(work).and_return(healthy)
    allow(Integrations::Github).to receive(:new).with(personal)
                                                .and_raise(Integrations::Base::RateLimited, 'rate limited')

    payload = panel.presenter.fetch

    expect(payload[:notifications].size).to eq(1)
    expect(payload[:partial]).to be(true)
    expect(work.reload.status).to eq('ok')
    expect(personal.reload.status).to eq('error')
  end

  it 'parks the panel in an error state when every account fails' do
    allow(Integrations::Github).to receive(:new).and_raise(Integrations::Base::Unavailable, 'GitHub down')

    expect { panel.presenter.refresh! }.not_to raise_error
    expect(panel.reload.data_status).to eq('error')
  end
end
