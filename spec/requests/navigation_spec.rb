# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Navigation' do
  let(:user) { create(:user) }

  # Every destination lives behind the one header button now, so a dropped item
  # is a page nothing links to.
  let(:destinations) do
    {
      'Countdowns' => '/countdowns',
      'Todos' => '/todos',
      'Habits' => '/habits',
      'Bookmarks' => '/bookmarks',
      'Connections' => '/connections',
      'Notifications' => '/notification_settings',
      'API tokens' => '/api_tokens',
      'Appearance' => '/appearance',
      'Account' => '/account'
    }
  end

  def menu_links
    response.parsed_body.css('#nav-menu a')
  end

  context 'when signed in' do
    before do
      sign_in user
      get root_path
    end

    it 'collapses the header into a single menu button' do
      expect(response.body).to include('aria-label="Menu"', 'aria-controls="nav-menu"')
    end

    it 'reaches every destination from the menu' do
      links = menu_links

      expect(links.to_h { |a| [a.text.strip, a['href']] }).to include(destinations)
    end

    it 'offers a way out' do
      expect(response.body).to include('Sign out')
    end

    it 'marks the page you are on, and only that one' do
      get bookmarks_path

      current = menu_links.select { |a| a['aria-current'] == 'page' }

      expect(current.map { |a| a.text.strip }).to eq(['Bookmarks'])
    end
  end

  it 'shows no menu to a signed-out visitor' do
    get new_user_session_path

    expect(response.body).not_to include('id="nav-menu"')
  end
end
