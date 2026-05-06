Rails.application.routes.draw do
  devise_for :users, skip: [:registrations]

  get "up" => "rails/health#show", as: :rails_health_check

  namespace :mcp, defaults: { format: :json } do
    namespace :v1 do
      resources :sites, only: [:index, :show] do
        member do
          get :diagnostics
        end
      end
    end
  end

  authenticate :user do
    root to: "dashboards#show"

    get "dashboard", to: "dashboards#show", as: :dashboard

    resources :organizations, only: [:show], path: "orgs"
    resources :sites, only: [:index, :show, :new, :create, :edit, :update] do
      resource :diagnostics, only: [:show], controller: "diagnostics"
      resources :cases, only: [:new, :create]
    end
    get "diagnostics", to: "diagnostics#index", as: :diagnostics
    resources :cases, only: [:index, :show, :new, :create] do
      member do
        post :add_note
        post :escalate
      end
    end

    resources :alarms, only: [:index] do
      member do
        post :acknowledge
        post :clear
      end
    end

    get  "customer_manager", to: "customer_manager#index"
    post "customer_manager", to: "customer_manager#create"

    resources :audit_logs, only: [:index]

    namespace :admin do
      resource :view_as, only: [:create, :destroy], controller: "view_as"
    end

    namespace :demo, defaults: { format: :json } do
      post "energy_analyst/message", to: "energy_analyst#message", as: :energy_analyst_message
    end
  end

  devise_scope :user do
    unauthenticated do
      root to: "devise/sessions#new", as: :unauthenticated_root
    end
  end
end
