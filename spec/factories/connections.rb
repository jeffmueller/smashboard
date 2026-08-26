# frozen_string_literal: true

FactoryBot.define do
  # Defaults to the news feed provider because its shape — exactly one secret
  # credential named `password`, plus a base_url setting — is what the specs
  # that use a bare `create(:connection)` lean on.
  factory :connection do
    user
    provider { 'news_feed' }
    label { 'Newsroom' }
    credentials { { 'password' => 'hunter2' } }
    settings { { 'base_url' => 'https://news.example.com' } }
  end
end
