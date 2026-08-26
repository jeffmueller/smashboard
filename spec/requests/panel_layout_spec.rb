# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Panel layout' do
  let(:user) { create(:user) }
  let(:panel) { user.panels.find_by!(kind: 'clock') }

  before { sign_in user }

  describe 'named widths' do
    # The board is a four-column grid, so these are the widths that tile without
    # leaving a ragged gap.
    it 'maps each name to a column span' do
      expect(Panel::SIZES).to eq({ 'small' => 1, 'medium' => 2, 'large' => 3, 'full' => 4 })
    end

    it 'reports the current width by name' do
      panel.update!(col_span: 3)

      expect(panel.size).to eq('large')
    end

    it 'resizes from the menu' do
      patch panel_path(panel), params: { panel: { size: 'full' } }

      expect(panel.reload.col_span).to eq(4)
    end

    it 'redraws just that panel rather than the whole board' do
      patch panel_path(panel), params: { panel: { size: 'full' } },
                               headers: { 'Accept' => 'text/vnd.turbo-stream.html' }

      expect(response.media_type).to eq('text/vnd.turbo-stream.html')
      expect(response.body).to include('replace', panel.to_stream_target)
    end

    it 'ignores a width that is not one of the presets' do
      panel.update!(col_span: 2)

      patch panel_path(panel), params: { panel: { size: 'enormous' } }

      expect(panel.reload.col_span).to eq(2)
    end

    it 'renders the chosen width on the board' do
      panel.update!(col_span: 4)

      get root_path

      expect(response.body).to include('lg:col-span-4')
    end
  end

  describe 'the panel menu' do
    # The panel clips its own content to keep its rounded corners, and a clipped
    # ancestor beats any z-index — an absolutely-positioned menu is cut off on a
    # short panel. The controller places it in viewport coordinates instead, so
    # reverting to `absolute` here would bring the bug straight back.
    it 'is positioned outside the panel it belongs to' do
      get root_path

      menu = response.body[/<div data-panel-menu-target="menu".*?>/m]
      expect(menu).to include('fixed')
      expect(menu).not_to include('absolute')
    end

    it 'is driven by the controller that measures and flips it' do
      get root_path

      expect(response.body).to include('data-controller="panel-menu"')
      expect(response.body).to include('data-panel-menu-target="button"')
    end

    # Removing the clip would be the other tempting fix, and would let panel
    # content bleed past the rounded corners.
    it 'leaves the panel clipping its own content' do
      get root_path

      expect(response.body).to match(/<section\s+id="panel_\d+"[^>]*/m)
      expect(response.body).to include('overflow-hidden rounded-xl')
    end
  end

  describe 'hiding' do
    it 'takes the panel off the board' do
      patch panel_path(panel), params: { panel: { enabled: false } }

      get root_path
      expect(response.body).not_to include(panel.to_stream_target)
    end

    it 'offers it back from the hidden strip' do
      panel.update!(enabled: false)

      get root_path

      expect(response.body).to include('Hidden', panel.display_title)
    end

    it 'removes the tile and refreshes the strip over Turbo' do
      patch panel_path(panel), params: { panel: { enabled: false } },
                               headers: { 'Accept' => 'text/vnd.turbo-stream.html' }

      expect(response.body).to include('remove', panel.to_stream_target)
      expect(response.body).to include('hidden-panels')
    end

    # The tile is not in the DOM to replace, and where it belongs depends on its
    # position among the others, so this reloads rather than streaming.
    it 'reloads the board when a panel comes back' do
      panel.update!(enabled: false)

      patch panel_path(panel), params: { panel: { enabled: true } },
                               headers: { 'Accept' => 'text/vnd.turbo-stream.html' }

      expect(response).to redirect_to(root_path)
      expect(panel.reload).to be_enabled
    end

    it 'shows no strip at all when nothing is hidden' do
      get root_path

      expect(response.body).not_to match(/>\s*Hidden\s*</)
    end

    it 'keeps a hidden panel out of the API dashboard too' do
      panel.update!(enabled: false)

      get '/api/v1/dashboard', headers: api_headers_for(user)

      expect(response.parsed_body['panels'].pluck('kind')).not_to include('clock')
    end
  end

  it "cannot resize somebody else's panel" do
    theirs = create(:user).panels.first

    patch panel_path(theirs), params: { panel: { size: 'full' } }

    expect(response).to have_http_status(:not_found)
    expect(theirs.reload.col_span).not_to eq(4)
  end

  it "cannot hide somebody else's panel" do
    theirs = create(:user).panels.first

    patch panel_path(theirs), params: { panel: { enabled: false } }

    expect(theirs.reload).to be_enabled
  end
end
