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
