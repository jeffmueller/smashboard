# frozen_string_literal: true

# Pin npm packages by running ./bin/importmap

pin 'application'
pin 'push'
# Pulled in on demand by the emoji picker — 66KB that most pages never need.
pin 'emoji_data'
pin '@hotwired/turbo-rails', to: 'turbo.min.js'
pin '@hotwired/stimulus', to: 'stimulus.min.js'
pin '@hotwired/stimulus-loading', to: 'stimulus-loading.js'
pin_all_from 'app/javascript/controllers', under: 'controllers'
