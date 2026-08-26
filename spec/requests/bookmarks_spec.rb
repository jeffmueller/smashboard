# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Bookmarks' do
  let(:user) { create(:user) }

  before { sign_in user }

  describe 'GET /bookmarks' do
    it 'lists the user\'s bookmarks' do
      create(:bookmark, user: user, title: 'Hacker News', url: 'https://news.ycombinator.com')

      get bookmarks_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('Hacker News')
    end
  end

  describe 'POST /bookmarks' do
    it 'adds a bookmark from just a url' do
      expect { post bookmarks_path, params: { bookmark: { url: 'github.com' } } }
        .to change(user.bookmarks, :count).by(1)

      expect(user.bookmarks.last).to have_attributes(url: 'https://github.com', title: 'github.com')
    end

    it 'appends to the end of the list' do
      create(:bookmark, user: user, position: 0)

      post bookmarks_path, params: { bookmark: { url: 'https://example.org' } }

      expect(user.bookmarks.ordered.last.position).to eq(1)
    end

    it 're-renders with an error rather than saving a javascript: url' do
      expect { post bookmarks_path, params: { bookmark: { url: 'javascript:alert(1)' } } }
        .not_to change(user.bookmarks, :count)

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include('must be a web address')
    end

    # The quick-add lives on the board and the form lives on this page, and the
    # response can't know which one it came from, so it carries both. A stream
    # aimed at an element the page doesn't have is ignored by Turbo.
    it 'updates the panel, the list and the form in one response' do
      post bookmarks_path, params: { bookmark: { url: 'https://example.org' } },
                           headers: { 'Accept' => 'text/vnd.turbo-stream.html' }

      expect(response.media_type).to eq('text/vnd.turbo-stream.html')
      expect(response.body).to include('example.org')
      targets = response.body.scan(/target="([^"]+)"/).flatten
      expect(targets).to include('bookmarks-list', 'new-bookmark', 'flash')
      expect(targets.grep(/\Apanel_/)).not_to be_empty
    end

    it 'reports a rejected url through the flash, which both pages show' do
      post bookmarks_path, params: { bookmark: { url: 'javascript:alert(1)' } },
                           headers: { 'Accept' => 'text/vnd.turbo-stream.html' }

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include('flash', 'must be a web address')
    end
  end

  describe 'PATCH /bookmarks/:id' do
    it 'renames a bookmark' do
      bookmark = create(:bookmark, user: user, title: 'Old')

      patch bookmark_path(bookmark), params: { bookmark: { title: 'New' } }

      expect(bookmark.reload.title).to eq('New')
    end

    it 'refuses to touch somebody else\'s bookmark' do
      theirs = create(:bookmark, user: create(:user), title: 'Theirs')

      patch bookmark_path(theirs), params: { bookmark: { title: 'Mine now' } }

      expect(response).to have_http_status(:not_found)
      expect(theirs.reload.title).to eq('Theirs')
    end
  end

  describe 'DELETE /bookmarks/:id' do
    it 'removes the bookmark' do
      bookmark = create(:bookmark, user: user)

      expect { delete bookmark_path(bookmark) }.to change(user.bookmarks, :count).by(-1)
    end

    it 'takes the row out of the list without a reload' do
      bookmark = create(:bookmark, user: user, title: 'Doomed')

      delete bookmark_path(bookmark), headers: { 'Accept' => 'text/vnd.turbo-stream.html' }

      expect(response.body).to include('bookmarks-list')
      expect(response.body).not_to include('Doomed')
    end
  end

  describe 'POST /bookmarks/reorder' do
    it 'applies the new order' do
      a = create(:bookmark, user: user, position: 0)
      b = create(:bookmark, user: user, position: 1)

      post reorder_bookmarks_path, params: { bookmark_ids: [b.id, a.id] }

      expect(response).to have_http_status(:no_content)
      expect(user.bookmarks.ordered.pluck(:id)).to eq([b.id, a.id])
    end

    it 'rejects an order with nothing the user owns' do
      post reorder_bookmarks_path, params: { bookmark_ids: [create(:bookmark).id] }

      expect(response).to have_http_status(:unprocessable_content)
    end
  end
end
