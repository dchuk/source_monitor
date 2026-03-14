# frozen_string_literal: true

SourceMonitor::Engine.routes.draw do
  get "/health", to: "health#show"
  get "/dashboard", to: "dashboard#index", as: :dashboard
  root to: "dashboard#index"
  resources :logs, only: :index
  resources :fetch_logs, only: :show
  resources :scrape_logs, only: :show
  resources :import_histories, only: [] do
    resource :dismissal, only: :create, controller: "import_history_dismissals"
  end
  resources :import_sessions, path: "import_opml", only: %i[new create show update destroy] do
    member do
      get "steps/:step", action: :show, as: :step
      patch "steps/:step", action: :update
    end
  end
  resources :items, only: %i[index show] do
    resource :scrape, only: :create, controller: "item_scrapes"
  end
  resources :bulk_scrape_enablements, only: :create
  resources :sources do
    resource :fetch, only: :create, controller: "source_fetches"
    resource :retry, only: :create, controller: "source_retries"
    resource :bulk_scrape, only: :create, controller: "source_bulk_scrapes"
    resource :health_check, only: :create, controller: "source_health_checks"
    resource :health_reset, only: :create, controller: "source_health_resets"
    resource :favicon_fetch, only: :create, controller: "source_favicon_fetches"
    resource :scrape_test, only: :create, controller: "source_scrape_tests"
  end
end
