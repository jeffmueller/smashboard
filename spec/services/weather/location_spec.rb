# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Weather::Location do
  let(:user) { create(:user, postal_code: '10001') }
  let(:connection) { create(:connection, user: user, provider: 'nws', label: 'Home', settings: {}) }
  let(:nyc) do
    { 'places' => [{ 'latitude' => '40.7484', 'longitude' => '-73.9967',
                     'place name' => 'New York City', 'state abbreviation' => 'NY' }] }
  end

  def stub_geocoder(postal_code, body)
    stub_request(:get, "https://api.zippopotam.us/us/#{postal_code}")
      .to_return(status: 200, body: body.to_json, headers: { 'Content-Type' => 'application/json' })
  end

  it 'uses explicit coordinates without geocoding anything' do
    connection.update!(settings: { 'latitude' => '38.8894', 'longitude' => '-77.0352', 'label' => 'The office' })

    result = described_class.for(connection)

    expect(result.latitude).to eq(38.8894)
    expect(result.longitude).to eq(-77.0352)
    expect(result.label).to eq('The office')
    expect(a_request(:get, /zippopotam/)).not_to have_been_made
  end

  it 'geocodes a postal code set on the connection' do
    connection.update!(settings: { 'postal_code' => '20500' })
    stub_geocoder('20500', { 'places' => [{ 'latitude' => '38.8987', 'longitude' => '-77.0352',
                                            'place name' => 'Washington', 'state abbreviation' => 'DC' }] })

    result = described_class.for(connection)

    expect(result.latitude).to eq(38.8987)
    expect(result.label).to eq('Washington, DC')
  end

  it "falls back to the user's own postal code" do
    stub_geocoder('10001', nyc)

    expect(described_class.for(connection).label).to eq('New York City, NY')
  end

  # Zip centroids don't move, so this is cached hard.
  it 'geocodes a postal code only once' do
    stub_geocoder('10001', nyc)
    allow(Rails).to receive(:cache).and_return(ActiveSupport::Cache::MemoryStore.new)

    2.times { described_class.for(connection) }

    expect(a_request(:get, %r{zippopotam\.us/us/10001})).to have_been_made.once
  end

  it 'says so plainly when there is no location at all' do
    user.update!(postal_code: nil)

    expect { described_class.for(connection) }
      .to raise_error(Integrations::Base::Unavailable, /no location set/)
  end

  it 'reports an unknown postal code' do
    stub_request(:get, %r{zippopotam\.us/us/99999}).to_return(status: 404, body: '{}')
    user.update!(postal_code: '99999')

    expect { described_class.for(connection) }
      .to raise_error(Integrations::Base::Unavailable, /could not look up postal code/)
  end
end
