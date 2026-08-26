# frozen_string_literal: true

namespace :smashboard do
  desc 'Generate a VAPID key pair for Web Push and print it for .env'
  task vapid: :environment do
    keys = WebPush.generate_key
    puts "VAPID_PUBLIC_KEY=#{keys.public_key}"
    puts "VAPID_PRIVATE_KEY=#{keys.private_key}"
  end

  desc 'Refresh every stale panel now'
  task refresh: :environment do
    RefreshStalePanelsJob.perform_now
  end
end
