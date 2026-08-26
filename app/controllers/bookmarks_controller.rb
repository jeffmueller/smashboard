# frozen_string_literal: true

class BookmarksController < ApplicationController
  before_action :set_bookmark, only: %i[update destroy]

  def index
    @bookmarks = current_user.bookmarks.ordered
    @bookmark = current_user.bookmarks.new
  end

  def create
    @bookmark = current_user.bookmarks.new(bookmark_params)
    @bookmark.position = current_user.bookmarks.next_position

    if @bookmark.save
      respond_to do |format|
        format.turbo_stream { render turbo_stream: refreshed_views }
        format.html { redirect_back_or_to(bookmarks_path) }
      end
    else
      respond_to do |format|
        format.turbo_stream { render turbo_stream: reported_error, status: :unprocessable_content }
        format.html { render_index_with_errors }
      end
    end
  end

  def update
    if @bookmark.update(bookmark_params)
      redirect_to bookmarks_path
    else
      render_index_with_errors
    end
  end

  def destroy
    @bookmark.destroy!
    respond_to do |format|
      format.turbo_stream { render turbo_stream: refreshed_views }
      format.html { redirect_to bookmarks_path }
    end
  end

  # Accepts the full ordered list of bookmark ids after a drag-and-drop.
  def reorder
    if current_user.bookmarks.apply_order(params[:bookmark_ids])
      head :no_content
    else
      head :unprocessable_content
    end
  end

  private

  def set_bookmark
    @bookmark = current_user.bookmarks.find(params.expect(:id))
  end

  # Bookmarks are edited from two places — the panel's quick-add on the board
  # and the management page — and a Turbo Stream aimed at an element that isn't
  # on the current page is simply ignored. So every change emits the update for
  # both, and whichever page the user is actually on takes the one it has.
  def refreshed_views
    [panel_stream, list_stream, form_stream, flash_stream].compact
  end

  def reported_error
    flash.now[:alert] = @bookmark.errors.full_messages.to_sentence
    [flash_stream]
  end

  def panel_stream
    panel = current_user.panels.find_by(kind: 'bookmarks')
    return nil if panel.nil?

    turbo_stream.replace(panel.to_stream_target, partial: 'panels/panel', locals: { panel: panel })
  end

  def list_stream
    turbo_stream.replace('bookmarks-list', partial: 'bookmarks/list',
                                           locals: { bookmarks: current_user.bookmarks.ordered })
  end

  # A fresh form, so the fields the user just submitted are cleared.
  def form_stream
    turbo_stream.replace('new-bookmark', partial: 'bookmarks/new_form',
                                         locals: { bookmark: current_user.bookmarks.new })
  end

  # Repainted even when there's nothing to say, to clear a previous error.
  def flash_stream
    turbo_stream.replace('flash', partial: 'shared/flash')
  end

  def render_index_with_errors
    @bookmarks = current_user.bookmarks.ordered
    render :index, status: :unprocessable_content
  end

  def bookmark_params
    params.expect(bookmark: %i[title url icon])
  end
end
