# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ConnectionProvider do
  it 'describes every provider a connection can have' do
    expect(described_class.keys).to match_array(Connection::PROVIDERS)
  end

  # A provider with no catalogue entry renders a form with no fields, which is
  # exactly the bug this catalogue exists to prevent.
  it 'gives every panel a provider it can actually be connected with' do
    required = ApplicationPanel.all.flat_map(&:required_providers).uniq

    expect(required - described_class.keys).to be_empty
  end

  it 'explains every provider' do
    providers = described_class.all

    providers.each do |provider|
      expect(provider.label).to be_present, "#{provider.key} has no label"
      expect(provider.summary).to be_present, "#{provider.key} has no summary"
      expect(provider.panel).to be_present, "#{provider.key} names no panel"
    end
  end

  it 'labels every field' do
    fields = described_class.all.flat_map { |provider| provider.settings + provider.credentials }

    expect(fields.map(&:label)).to all(be_present)
    expect(fields.map(&:key)).to all(match(/\A[a-z_]+\z/))
  end

  it 'treats every credential as secret' do
    credentials = described_class.all.flat_map(&:credentials)

    expect(credentials).to all(be_secret)
  end

  # A provider with no credential field is either genuinely keyless or gets its
  # credential from an authorization flow. Anything else is a form with nothing
  # to fill in.
  it 'only lets a provider skip credentials for a reason' do
    unexplained = described_class.all.select { |provider| provider.credentials.empty? && !provider.oauth? }

    expect(unexplained.map(&:key)).to eq(['nws'])
  end

  it 'gives an oauth provider no credential fields to type into' do
    described_class.all.select(&:oauth?).each do |provider|
      expect(provider.credentials).to be_empty, "#{provider.key} both signs in and asks for a secret"
    end
  end

  it 'matches what the Connection model reports as required fields' do
    providers = described_class.all

    providers.each do |provider|
      expect(Connection.fields_for(provider.key)).to eq(provider.field_keys)
    end
  end

  it 'returns an empty field set for something that is not a provider' do
    expect(Connection.fields_for('not-a-provider')).to eq({ settings: [], credentials: [] })
  end
end
