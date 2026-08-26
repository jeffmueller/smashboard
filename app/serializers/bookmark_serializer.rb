# frozen_string_literal: true

class BookmarkSerializer
  def initialize(bookmark)
    @bookmark = bookmark
  end

  def as_json(*)
    {
      id: @bookmark.id,
      title: @bookmark.title,
      url: @bookmark.url,
      host: @bookmark.host,
      icon: @bookmark.icon.presence,
      initial: @bookmark.initial,
      position: @bookmark.position
    }
  end
end
