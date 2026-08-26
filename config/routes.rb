# frozen_string_literal: true

Rails.application.routes.draw do
  devise_for :users, controllers: { registrations: 'users/registrations' }

  root 'dashboard#show'

  # Public, and linked from the sign-in screen: Google's OAuth consent screen
  # requires both to be reachable without an account.
  get 'privacy', to: 'legal#privacy'
  get 'terms', to: 'legal#terms'

  resources :panels, only: %i[create update destroy] do
    collection { post :reorder }
    member { post :refresh }
  end

  resources :countdowns do
    member { post :dismiss }
  end

  resources :todos, except: %i[show new edit] do
    member do
      post :complete
      post :uncomplete
    end
  end

  resources :bookmarks, except: %i[show new edit] do
    collection { post :reorder }
  end

  resources :habits, except: %i[show new edit] do
    collection { post :reorder }
    member do
      post :toggle
      post :archive
      post :unarchive
    end
  end

  resources :todo_projects, only: %i[index create update destroy]
  resources :connections, except: :show
  resources :api_tokens, only: %i[index create destroy]
  resource :notification_settings, only: %i[show update]
  # Connect-with-Google. The callback URL below is what has to be registered in
  # the Google Cloud console as an authorized redirect URI.
  namespace :oauth do
    get 'google', to: 'google#authorize'
    get 'google/callback', to: 'google#callback'
    get 'slack', to: 'slack#authorize'
    get 'slack/callback', to: 'slack#callback'
  end

  resource :appearance, only: %i[show update]
  resource :account, only: %i[show update] do
    patch :password
  end

  # entity_id carries a dot ("camera.front_door"), which Rails would otherwise
  # read as a format separator, so the segment is constrained and the format
  # suffix disabled.
  get 'cameras/:connection_id/:entity_id/snapshot',
      to: 'camera_snapshots#show',
      as: :camera_snapshot,
      constraints: { entity_id: /camera\.[a-z0-9_]+/ },
      format: false

  resources :push_subscriptions, only: %i[create destroy], param: :endpoint

  namespace :api do
    namespace :v1 do
      resource :dashboard, only: :show

      resources :panels, only: %i[index show update destroy] do
        collection { post :reorder }
        member { post :refresh }
      end

      resources :countdowns do
        member { post :dismiss }
      end

      resources :bookmarks do
        collection { post :reorder }
      end

      resources :habits do
        collection { post :reorder }
        member do
          post :toggle
          post :archive
          post :unarchive
        end
      end

      # Pushed by the machines that run a coding agent; see script/smashboard-usage-reporter.
      resources :agent_usage, only: %i[index create destroy], controller: 'agent_usage'

      resources :todos do
        member do
          post :complete
          post :uncomplete
        end
      end

      resources :connections, only: %i[index create update destroy]
    end
  end

  # PWA
  get 'manifest' => 'rails/pwa#manifest', as: :pwa_manifest
  get 'service-worker' => 'rails/pwa#service_worker', as: :pwa_service_worker

  # Health check for uptime monitors and container orchestrators.
  get 'up' => 'rails/health#show', as: :rails_health_check
end
