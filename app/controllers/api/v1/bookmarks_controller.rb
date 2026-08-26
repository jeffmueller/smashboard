# frozen_string_literal: true

module Api
  module V1
    class BookmarksController < BaseController
      before_action :set_bookmark, only: %i[show update destroy]

      def index
        render json: { bookmarks: current_user.bookmarks.ordered.map { |b| BookmarkSerializer.new(b).as_json } }
      end

      def show
        render json: BookmarkSerializer.new(@bookmark).as_json
      end

      def create
        bookmark = current_user.bookmarks.new(bookmark_params)
        bookmark.position = current_user.bookmarks.next_position
        bookmark.save!
        render json: BookmarkSerializer.new(bookmark).as_json, status: :created
      end

      def update
        @bookmark.update!(bookmark_params)
        render json: BookmarkSerializer.new(@bookmark).as_json
      end

      def destroy
        @bookmark.destroy!
        head :no_content
      end

      def reorder
        return head :unprocessable_content unless current_user.bookmarks.apply_order(params[:bookmark_ids])

        head :no_content
      end

      private

      def set_bookmark
        @bookmark = current_user.bookmarks.find(params.expect(:id))
      end

      def bookmark_params
        params.expect(bookmark: %i[title url icon position])
      end
    end
  end
end
