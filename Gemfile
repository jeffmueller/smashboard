# frozen_string_literal: true

source 'https://rubygems.org'

gem 'rails', '~> 8.1.3', '>= 8.1.3.1'
# The modern asset pipeline for Rails [https://github.com/rails/propshaft]
gem 'propshaft'
# Use postgresql as the database for Active Record
gem 'pg', '~> 1.1'
# Use the Puma web server [https://github.com/puma/puma]
gem 'puma', '>= 5.0'
# Use JavaScript with ESM import maps [https://github.com/rails/importmap-rails]
gem 'importmap-rails'
# Hotwire's SPA-like page accelerator [https://turbo.hotwired.dev]
gem 'turbo-rails'
# Hotwire's modest JavaScript framework [https://stimulus.hotwired.dev]
gem 'stimulus-rails'
# Use Tailwind CSS [https://github.com/rails/tailwindcss-rails]
gem 'tailwindcss-rails'

# Windows does not include zoneinfo files, so bundle the tzinfo-data gem
gem 'tzinfo-data', platforms: %i[windows jruby]

# Use the database-backed adapters for Rails.cache, Active Job, and Action Cable
gem 'solid_cable'
gem 'solid_cache'
gem 'solid_queue'

# Reduces boot times through caching; required in config/boot.rb
gem 'bootsnap', require: false

# Add HTTP asset caching/compression and X-Sendfile acceleration to Puma [https://github.com/basecamp/thruster/]
gem 'thruster', require: false

# CSV is a bundled gem as of Ruby 3.4 and must be declared explicitly
gem 'csv'

# --- Authentication & authorization -----------------------------------------
gem 'bcrypt', '~> 3.1'
gem 'devise'
# Throttle login + API token attempts.
gem 'rack-attack'

# --- Panels, scheduling, notifications --------------------------------------
# Recurrence rules (RFC 5545 RRULE) drive both recurring countdowns and
# repeating todos, so they share one engine.
gem 'ice_cube'
# PWA push delivery for notifications.
gem 'web-push'
# Pagination for the JSON API.
gem 'kaminari'

# --- Integrations -----------------------------------------------------------
# IMAP unread counts + message previews (Gmail, Fastmail).
gem 'mail'
gem 'net-imap', '>= 0.5'
# CalDAV / .ics calendar parsing (Fastmail, Google).
gem 'icalendar'
# Shared HTTP client for GitHub, Slack, Anthropic, NWS, Home Assistant, news feeds.
gem 'faraday'
gem 'faraday-retry'
# OAuth2 flows for Google (Gmail/Calendar) and Slack.
gem 'oauth2'
# GitHub notifications + pull requests.
gem 'octokit'
# Scrub HTML out of email previews.
gem 'nokogiri'

group :development, :test do
  # See https://guides.rubyonrails.org/debugging_rails_applications.html#debugging-with-the-debug-gem
  gem 'debug', platforms: %i[mri windows], require: 'debug/prelude'

  # Audits gems for known security defects (use config/bundler-audit.yml to ignore issues)
  gem 'bundler-audit', require: false

  # Static analysis for security vulnerabilities [https://brakemanscanner.org/]
  gem 'brakeman', require: false

  gem 'awesome_print'
  gem 'factory_bot_rails'
  gem 'faker'
  gem 'pry-rails'
  gem 'rspec-rails'
  gem 'rubocop'
  gem 'rubocop-factory_bot'
  gem 'rubocop-rails'
  gem 'rubocop-rspec'
  gem 'rubocop-rspec_rails'
  gem 'shoulda-matchers'
  gem 'webmock'
end

group :development do
  # Use console on exceptions pages [https://github.com/rails/web-console]
  gem 'web-console'

  gem 'annotaterb'
  gem 'dotenv-rails'
  gem 'lefthook'
  gem 'overmind'
end

group :test do
  gem 'capybara'
  gem 'selenium-webdriver'
end
