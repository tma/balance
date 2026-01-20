Rails.application.routes.draw do
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Render dynamic PWA files from app/views/pwa/* (remember to link manifest in application.html.erb)
  # get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  # get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker

  # Dashboard as root
  root "dashboard#home"
  get "home", to: "dashboard#home", as: :home
  get "cash-flow", to: "dashboard#cash_flow", as: :cash_flow
  get "net-worth", to: "dashboard#net_worth", as: :net_worth

  # Main resources
  resources :accounts, except: :show
  resources :assets, path: "financial-assets" do
    resources :valuations, only: [ :edit, :update, :destroy ], controller: "asset_valuations"
    collection do
      patch :sort
    end
    member do
      patch :archive
      patch :unarchive
    end
  end
  resources :asset_groups, path: "asset-groups", except: [ :index, :show ] do
    collection do
      patch :sort
    end
  end
  resources :transactions
  resources :budgets

  # Transaction import
  resources :imports, only: [ :index, :new, :create, :show, :destroy ] do
    member do
      post :confirm
      post :reprocess
      get :status
    end
  end

  # Bulk update valuations for all assets
  get "valuations", to: "asset_valuations#bulk_edit", as: :update_valuations
  patch "valuations", to: "asset_valuations#bulk_update"
  post "valuations/apply-broker-values", to: "asset_valuations#apply_broker_values", as: :apply_broker_values

  # Admin namespace for master data
  namespace :admin do
    resources :currencies
    resources :account_types
    resources :asset_types
    resources :categories
    resources :broker_connections, path: "brokers" do
      collection do
        post :test_connection
      end
      resources :broker_positions, path: "positions", as: :positions, only: [ :index, :show, :edit, :update ] do
        collection do
          patch :bulk_update
        end
        resources :position_valuations, path: "valuations", as: :valuations, only: [ :update, :destroy ]
      end
    end
  end
end
