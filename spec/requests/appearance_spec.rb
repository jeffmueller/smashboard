# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Appearance' do
  let(:user) { create(:user) }

  before { sign_in user }

  it 'lists every theme with its swatches' do
    get appearance_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include('Follow the system')
    Theme.all.first(3).each { |theme| expect(response.body).to include(theme.name) }
  end

  it 'saves an explicit theme' do
    patch appearance_path, params: { user: { theme: 'tokyo-night' } }

    expect(user.reload.theme).to eq('tokyo-night')
  end

  # Nil is what makes the stylesheet's prefers-color-scheme block take over, so
  # "system" has to normalise to nil rather than be stored as a slug.
  it 'stores following the system as nothing at all' do
    user.update!(theme: 'tokyo-night')

    patch appearance_path, params: { user: { theme: Theme::SYSTEM } }

    expect(user.reload.theme).to be_nil
  end

  it 'refuses a theme that does not exist' do
    user.update!(theme: 'tokyo-night')

    patch appearance_path, params: { user: { theme: 'definitely-not-a-theme' } }

    expect(response).to have_http_status(:unprocessable_content)
    expect(user.reload.theme).to eq('tokyo-night')
  end

  # Per device, in the browser (app/javascript/omarchy_theme.js) — so all the
  # server can do is offer the switch and hand the boot script what it needs.
  describe 'following the Omarchy desktop theme' do
    it 'offers it on the appearance page, outside the account form' do
      get appearance_path

      page = response.parsed_body
      toggle = page.at_css('[data-omarchy-theme-target="toggle"]')
      expect(toggle).to be_present
      expect(toggle.ancestors('form')).to be_empty
    end

    it "tells the boot script every token and each mode's fallback theme" do
      get root_path

      config = JSON.parse(response.parsed_body.at_css('meta[name="omarchy-theme"]')['content'])
      expect(config['tokens']).to eq(Theme::TOKENS)
      expect([config['dark'], config['light']]).to all(satisfy { |slug| Theme.find(slug).present? })
    end

    # Signed out it still follows the desktop: the setting is the browser's.
    it 'paints before first paint on every layout' do
      sign_out user

      [new_user_session_path, privacy_path].each do |path|
        get path
        expect(response.body).to include('meta name="omarchy-theme"')
      end
    end

    # The boot script and the module share two storage keys and nothing else
    # ties them together.
    it 'has the boot script and the module agree on where the setting lives' do
      boot = Rails.root.join('app/views/layouts/_omarchy_boot.html.erb').read
      module_source = Rails.root.join('app/javascript/omarchy_theme.js').read

      %w[appearance.followOmarchyTheme appearance.omarchyTokens].each do |key|
        expect(boot).to include(%("#{key}"))
        expect(module_source).to include(%("#{key}"))
      end
    end
  end

  describe 'what the layout renders' do
    it 'puts the chosen theme on the html element' do
      user.update!(theme: 'gruvbox')

      get root_path

      expect(response.body).to include('data-theme="gruvbox"')
    end

    # No attribute means prefers-color-scheme decides, which is what keeps the
    # system option from flashing the wrong theme on load.
    it 'omits the attribute entirely when following the system' do
      user.update!(theme: nil)

      get root_path

      expect(response.body).not_to include('data-theme=')
    end

    it 'sets the browser theme colour from the resolved theme' do
      user.update!(theme: 'gruvbox')

      get root_path

      expect(response.body).to include(%(content="#{Theme.find('gruvbox').token('canvas')}"))
    end
  end
end
