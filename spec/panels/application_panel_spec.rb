# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ApplicationPanel do
  let(:user) { create(:user) }

  describe '.for' do
    it 'resolves a panel class by kind' do
      panel = create(:panel, user: user, kind: 'github_pull_requests')

      expect(described_class.for(panel)).to be_a(GithubPullRequestsPanel)
    end

    it 'raises on a kind with no class' do
      panel = build(:panel, user: user, kind: 'nonsense')

      expect { described_class.for(panel) }.to raise_error(described_class::UnknownPanel)
    end

    it 'has no panel left unbuilt' do
      pending_kinds = Panel::KINDS.select { |kind| "#{kind.camelize}Panel".constantize.pending? }

      expect(pending_kinds).to be_empty
    end

    it 'has a class for every declared kind' do
      expect(Panel::KINDS.map { |kind| "#{kind.camelize}Panel".safe_constantize }).to all(be_present)
    end
  end

  describe 'the notification hook' do
    let(:panel) { create(:panel, user: user, kind: 'news') }

    before { create(:connection, user: user, provider: 'news_feed') }

    def stub_fetch(presenter, payload)
      allow(presenter).to receive(:fetch).and_return(payload)
    end

    it 'hands the previous payload to notify after a successful refresh' do
      presenter = panel.presenter
      stub_fetch(presenter, { story: { headline: 'Second' } })
      panel.update!(data: { story: { headline: 'First' } })
      allow(presenter).to receive(:notify)

      presenter.refresh!

      expect(presenter).to have_received(:notify).with(hash_including(story: hash_including(headline: 'First')))
    end

    # The wrapper refresh! calls is deliberately not named `announce`: panels
    # define their own announce-ish helpers, and an arity-mismatched override
    # would fail inside refresh!'s rescue and show up as a mystery panel error
    # rather than a notification bug.
    it 'does not collide with a panel\'s own private helpers' do
      overridden = Panel::KINDS.filter_map do |kind|
        klass = "#{kind.camelize}Panel".safe_constantize
        next if klass.nil?

        kind if klass.private_method_defined?(:deliver_notifications, false)
      end

      expect(overridden).to be_empty
    end

    it 'logs a notification failure without failing the refresh' do
      presenter = panel.presenter
      stub_fetch(presenter, { story: { headline: 'Second' } })
      allow(presenter).to receive(:notify).and_raise(StandardError, 'notifier exploded')

      expect(presenter.refresh!).to be(true)
      expect(panel.reload.data_status).to eq('ok')
    end
  end
end
