# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Meetings::VideoLink do
  describe '.extract' do
    it 'returns nil when nothing looks like a meeting' do
      expect(described_class.extract(nil, '', 'Conference room B')).to be_nil
    end

    {
      'Zoom' => 'https://acme.zoom.us/j/98765432101?pwd=abcDEF',
      'Google Meet' => 'https://meet.google.com/abc-defg-hij',
      'Microsoft Teams' => 'https://teams.microsoft.com/l/meetup-join/19%3ameeting_abc%40thread.v2/0',
      'Webex' => 'https://acme.webex.com/meet/dana',
      'Whereby' => 'https://whereby.com/smashboard',
      'Jitsi' => 'https://meet.jit.si/SmashboardStandup',
      'BlueJeans' => 'https://acme.bluejeans.com/123456789',
      'Chime' => 'https://chime.aws/1234567890',
      'Slack' => 'https://acme.slack.com/huddle/T123/C456'
    }.each do |provider, url|
      it "recognises #{provider}" do
        result = described_class.extract(url)

        expect(result.provider).to eq(provider)
        expect(result.url).to eq(url)
      end
    end

    it 'recognises a Zoom government host' do
      expect(described_class.extract('https://acme.zoomgov.com/j/123').provider).to eq('Zoom')
    end

    it 'takes the first source that matches, so an explicit field beats a description' do
      result = described_class.extract(
        'https://meet.google.com/aaa-bbbb-ccc',
        'https://acme.zoom.us/j/999'
      )

      expect(result.provider).to eq('Google Meet')
    end

    it 'skips sources that are blank and keeps looking' do
      result = described_class.extract(nil, '', 'https://acme.zoom.us/j/555')

      expect(result.url).to eq('https://acme.zoom.us/j/555')
    end

    # A Zoom invite body contains the join link plus support and dial-in links.
    # Matching "any URL" would reliably pick the wrong one.
    it 'ignores non-join links from the same provider' do
      description = <<~TEXT
        Join here: https://acme.zoom.us/j/98765432101?pwd=xyz
        Need help? https://support.zoom.us/hc/en-us/articles/201362193
      TEXT

      expect(described_class.extract(description).url).to eq('https://acme.zoom.us/j/98765432101?pwd=xyz')
    end

    it 'does not match a bare provider homepage' do
      expect(described_class.extract('See https://zoom.us for details')).to be_nil
    end

    it 'decodes HTML entities in a description' do
      html = '<p>Join <a href="https://acme.zoom.us/j/123?pwd=a&amp;uname=b">here</a></p>'

      expect(described_class.extract(html).url).to eq('https://acme.zoom.us/j/123?pwd=a&uname=b')
    end

    it 'unfolds escaped newlines from ICS text' do
      expect(described_class.extract('Agenda\\nJoin: https://meet.google.com/abc-defg-hij\\nBye').url)
        .to eq('https://meet.google.com/abc-defg-hij')
    end

    it 'strips punctuation that prose glues onto the end of a URL' do
      expect(described_class.extract('Use https://meet.google.com/abc-defg-hij.').url)
        .to eq('https://meet.google.com/abc-defg-hij')

      expect(described_class.extract('(https://meet.google.com/abc-defg-hij)').url)
        .to eq('https://meet.google.com/abc-defg-hij')
    end
  end
end
