# frozen_string_literal: true

require 'sidekiq/web'
require 'sidekiq-status/web'
if Octobox.config.sidekiq_schedule_enabled?
  require 'sidekiq-scheduler/web'
end
require 'admin_constraint'

Rails.application.routes.draw do
  root to: 'notifications#index'

  constraints AdminConstraint.new do
    namespace :admin do
      mount Sidekiq::Web => "/sidekiq"
    end

    get '/admin', to: 'admin#index', as: :admin
  end

  get :login,  to: 'sessions#new'
  get :logout, to: 'sessions#destroy'

  scope :auth do
    match '/:provider/callback', to: 'sessions#create',  via: [:get, :post]
    match :failure,              to: 'sessions#failure', via: [:get, :post]
  end

  resources :notifications, only: :index, format: true, constraints: { format: :json }
  resources :notifications, only: [] do
    collection do
      post :archive_selected
      post :sync
      get  :sync
      get  :syncing
      post :mute_selected
      post :mark_read_selected
      get  :unread_count
    end

    member do
      post :star
      post :mark_read
    end
  end

  get '/documentation', to: 'pages#documentation'
  get '/support', to: redirect('/documentation#support')

  post '/hooks/github', to: 'hooks#create'

  if Octobox.octobox_io?
    get '/privacy', to: 'pages#privacy'
    get '/terms', to: 'pages#terms'
  end

  get '/settings/saved-searches', to: 'saved_searches#index'

  get '/settings', to: 'users#edit'
  resources :users, only: [:update, :destroy] do
    collection do
      scope format: true, constraints: { format: 'json' } do
        get :profile
      end
    end
  end
end
