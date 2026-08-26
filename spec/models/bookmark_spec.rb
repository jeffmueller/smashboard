# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Bookmark do
  let(:user) { create(:user) }

  describe 'url normalization' do
    it 'assumes https for a bare host, which is what people actually type' do
      bookmark = user.bookmarks.create!(title: 'GitHub', url: 'github.com')

      expect(bookmark.url).to eq('https://github.com')
    end

    it 'leaves an explicit scheme alone' do
      bookmark = user.bookmarks.create!(title: 'Local', url: 'http://localhost:3000/dash')

      expect(bookmark.url).to eq('http://localhost:3000/dash')
    end

    it 'treats a bare host and port as a host, not a scheme' do
      bookmark = user.bookmarks.create!(title: 'Dev', url: 'localhost:3000')

      expect(bookmark.url).to eq('https://localhost:3000')
    end

    it 'trims surrounding whitespace from a pasted url' do
      bookmark = user.bookmarks.create!(title: 'Padded', url: '  https://example.com/x  ')

      expect(bookmark.url).to eq('https://example.com/x')
    end
  end

  describe 'scheme allow-list' do
    # These are the reason the check is an allow-list and not a parse: both
    # execute in the page when the rendered link is clicked.
    it 'rejects javascript: urls' do
      bookmark = user.bookmarks.new(title: 'Bad', url: 'javascript:alert(1)')

      expect(bookmark).not_to be_valid
      expect(bookmark.errors[:url]).to include('must be a web address')
    end

    it 'rejects data: urls' do
      bookmark = user.bookmarks.new(title: 'Bad', url: 'data:text/html,<script>alert(1)</script>')

      expect(bookmark).not_to be_valid
    end

    # Prepending a scheme to something that already has one would hide the
    # dangerous scheme from the allow-list instead of tripping it.
    it 'does not rescue a javascript: url by prepending https' do
      bookmark = user.bookmarks.new(title: 'Bad', url: 'javascript:alert(1)')

      bookmark.valid?

      expect(bookmark.url).to eq('javascript:alert(1)')
    end

    it 'rejects a scheme smuggled past the check with a control character' do
      bookmark = user.bookmarks.new(title: 'Bad', url: "java\tscript:alert(1)")

      expect(bookmark).not_to be_valid
    end

    it 'rejects a scheme with no host' do
      bookmark = user.bookmarks.new(title: 'Bad', url: 'https://')

      expect(bookmark).not_to be_valid
    end

    it 'rejects something that will not parse as a url at all' do
      bookmark = user.bookmarks.new(title: 'Bad', url: 'http://[oops')

      expect(bookmark).not_to be_valid
    end

    it 'accepts http and https' do
      expect(user.bookmarks.new(title: 'A', url: 'http://example.com')).to be_valid
      expect(user.bookmarks.new(title: 'B', url: 'https://example.com')).to be_valid
    end
  end

  describe 'title' do
    it 'falls back to the host when none is given' do
      bookmark = user.bookmarks.create!(url: 'https://www.github.com/anthropics')

      expect(bookmark.title).to eq('github.com')
    end

    it 'is required when the url has no host to fall back on' do
      expect(user.bookmarks.new(url: 'not a url')).not_to be_valid
    end
  end

  describe '#host' do
    it 'drops the www prefix, which is noise in a small tile' do
      expect(build(:bookmark, url: 'https://www.example.com/a/b').host).to eq('example.com')
    end

    it 'keeps a non-default port, which distinguishes machines on a home network' do
      expect(build(:bookmark, url: 'http://homeassistant.local:8123').host).to eq('homeassistant.local:8123')
    end

    it 'drops the port when it is the scheme default' do
      expect(build(:bookmark, url: 'https://example.com:443/a').host).to eq('example.com')
    end

    it 'is nil rather than raising for an unparseable url' do
      bookmark = build(:bookmark)
      bookmark.url = 'http://[oops'

      expect(bookmark.host).to be_nil
    end
  end

  describe '#initial' do
    it 'is the first letter of the title, upcased' do
      expect(build(:bookmark, title: 'hacker news').initial).to eq('H')
    end

    it 'falls back to a placeholder rather than an empty badge' do
      bookmark = build(:bookmark)
      bookmark.title = ' '

      expect(bookmark.initial).to eq('?')
    end
  end
end
