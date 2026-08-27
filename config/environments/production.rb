# frozen_string_literal: true

require 'active_support/core_ext/integer/time'

Rails.application.configure do
  # Settings specified here will take precedence over those in config/application.rb.

  # Code is not reloaded between requests.
  config.enable_reloading = false

  # Eager load code on boot for better performance and memory savings (ignored by Rake tasks).
  config.eager_load = true

  # Full error reports are disabled.
  config.consider_all_requests_local = false

  # Turn on fragment caching in view templates.
  config.action_controller.perform_caching = true

  # Cache assets for far-future expiry since they are all digest stamped.
  config.public_file_server.headers = { 'cache-control' => "public, max-age=#{1.year.to_i}" }

  # Enable serving of images, stylesheets, and JavaScripts from an asset server.
  # config.asset_host = "http://assets.example.com"

  # Store uploaded files on the local file system (see config/storage.yml for options).
  config.active_storage.service = :local

  # Nothing in this app attaches an image, so the variant processor is never
  # reached — without this it warns about a missing image_processing gem on
  # every boot and every rake task.
  config.active_storage.variant_processor = :disabled

  # Deployments differ on who terminates TLS, and getting this wrong is silent
  # rather than loud, so it is configuration.
  #
  #   default (unset)          — a reverse proxy in front terminating TLS and
  #                              forwarding plain HTTP over the loopback, which
  #                              is the nginx/Raspberry Pi setup in the README.
  #                              assume_ssl stops Rails calling that connection
  #                              insecure and redirecting to https forever.
  #   SMASHBOARD_FORCE_SSL=false — served over plain HTTP, e.g. a NAS on the LAN
  #                              at http://nas.local:3000 with nothing in front.
  #
  # Leaving both on for a plain-HTTP host does not merely redirect: force_ssl
  # also marks the session cookie `secure`, so the browser never sends it back
  # and signing in appears to succeed and then bounces straight to the login
  # page again. Turn them off together or not at all.
  config.assume_ssl = ENV.fetch('SMASHBOARD_FORCE_SSL', 'true') != 'false'
  config.force_ssl = ENV.fetch('SMASHBOARD_FORCE_SSL', 'true') != 'false'

  # The health check has to answer over plain HTTP: it's what the reverse proxy
  # and any uptime monitor hit, and a 301 is not a health signal.
  config.ssl_options = { redirect: { exclude: ->(request) { request.path == '/up' } } }

  # Log to STDOUT with the current request id as a default log tag.
  config.log_tags = [:request_id]
  config.logger   = ActiveSupport::TaggedLogging.logger($stdout)

  # Change to "debug" to log everything (including potentially personally-identifiable information!).
  config.log_level = ENV.fetch('RAILS_LOG_LEVEL', 'info')

  # Prevent health checks from clogging up the logs.
  config.silence_healthcheck_path = '/up'

  # Don't log any deprecations.
  config.active_support.report_deprecations = false

  # Replace the default in-process memory cache store with a durable alternative.
  config.cache_store = :solid_cache_store

  # Replace the default in-process and non-durable queuing backend for Active Job.
  config.active_job.queue_adapter = :solid_queue
  config.solid_queue.connects_to = { database: { writing: :queue } }

  # Ignore bad email addresses and do not raise email delivery errors.
  # Set this to true and configure the email server for immediate delivery to raise delivery errors.
  # config.action_mailer.raise_delivery_errors = false

  # Devise sends password-reset links, so this has to be the real host or the
  # link in the mail points nowhere.
  config.action_mailer.default_url_options = { host: ENV.fetch('APP_HOST', 'localhost') }

  # Specify outgoing SMTP server. Remember to add smtp/* credentials via bin/rails credentials:edit.
  # config.action_mailer.smtp_settings = {
  #   user_name: Rails.application.credentials.dig(:smtp, :user_name),
  #   password: Rails.application.credentials.dig(:smtp, :password),
  #   address: "smtp.example.com",
  #   port: 587,
  #   authentication: :plain
  # }

  # Enable locale fallbacks for I18n (makes lookups for any locale fall back to
  # the I18n.default_locale when a translation cannot be found).
  config.i18n.fallbacks = true

  # Do not dump schema after migrations.
  config.active_record.dump_schema_after_migration = false

  # Only use :id for inspections in production.
  config.active_record.attributes_for_inspect = [:id]

  # DNS rebinding protection. APP_HOST is the name the app is served under; a
  # request arriving with any other Host header is not for us.
  config.hosts << ENV['APP_HOST'] if ENV['APP_HOST'].present?

  # The health check is requested over the loopback by its address rather than
  # its name, which would otherwise fail host authorization.
  config.host_authorization = { exclude: ->(request) { request.path == '/up' } }
end
