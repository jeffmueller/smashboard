# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Bookmarks' do
  let(:user) { create(:user) }
  let(:headers) { api_headers_for(user) }

  it 'lists the caller\'s bookmarks in order' do
    create(:bookmark, user: user, title: 'Second', position: 1)
    create(:bookmark, user: user, title: 'First', position: 0)

    get '/api/v1/bookmarks', headers: headers

    expect(response.parsed_body['bookmarks'].pluck('title')).to eq(%w[First Second])
  end

  it 'scopes to the calling user' do
    other = create(:bookmark, user: create(:user))

    get "/api/v1/bookmarks/#{other.id}", headers: headers

    expect(response).to have_http_status(:not_found)
  end

  it 'creates from a bare host and appends to the end' do
    create(:bookmark, user: user, position: 0)

    post '/api/v1/bookmarks', params: { bookmark: { url: 'github.com' } }, headers: headers, as: :json

    expect(response).to have_http_status(:created)
    expect(response.parsed_body).to include('url' => 'https://github.com', 'title' => 'github.com', 'position' => 1)
  end

  it 'refuses a javascript: url' do
    post '/api/v1/bookmarks', params: { bookmark: { url: 'javascript:alert(1)' } }, headers: headers, as: :json

    expect(response).to have_http_status(:unprocessable_content)
  end

  it 'updates and deletes' do
    bookmark = create(:bookmark, user: user, title: 'Old')

    patch "/api/v1/bookmarks/#{bookmark.id}", params: { bookmark: { title: 'New' } }, headers: headers, as: :json
    expect(response.parsed_body['title']).to eq('New')

    delete "/api/v1/bookmarks/#{bookmark.id}", headers: headers
    expect(response).to have_http_status(:no_content)
  end

  it 'reorders' do
    a = create(:bookmark, user: user, position: 0)
    b = create(:bookmark, user: user, position: 1)

    post '/api/v1/bookmarks/reorder', params: { bookmark_ids: [b.id, a.id] }, headers: headers, as: :json

    expect(response).to have_http_status(:no_content)
    expect(user.bookmarks.ordered.pluck(:id)).to eq([b.id, a.id])
  end

  it 'requires a token' do
    get '/api/v1/bookmarks'

    expect(response).to have_http_status(:unauthorized)
  end
end
