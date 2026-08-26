# frozen_string_literal: true

# Links to the sites and web apps you want one click away.
#
# Payload contract:
#   { bookmarks: [{ id:, title:, url:, host:, icon:, initial: }] }
class BookmarksPanel < ApplicationPanel
  class << self
    def title = 'Bookmarks'
    def description = 'Quick links to your sites and web apps'
    def default_col_span = 2
  end

  def build
    { bookmarks: user.bookmarks.ordered.map { |bookmark| serialize(bookmark) } }
  end

  private

  # `host` is dropped when it only repeats the title, which is what an
  # auto-titled bookmark looks like — the tile would otherwise print it twice.
  def serialize(bookmark)
    host = bookmark.host

    {
      id: bookmark.id,
      title: bookmark.title,
      url: bookmark.url,
      host: (host unless host == bookmark.title),
      icon: bookmark.icon.presence,
      initial: bookmark.initial
    }
  end
end
