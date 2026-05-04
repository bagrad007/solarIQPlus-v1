Rails.application.routes.draw do
  devise_for :users, skip: [:registrations]

  get "up" => "rails/health#show", as: :rails_health_check

  authenticate :user do
    root to: "dashboards#show"

    get "dashboard", to: "dashboards#show", as: :dashboard

    resources :organizations, only: [:show], path: "orgs"
    resources :sites, only: [:index, :show, :new, :create, :edit, :update] do
      resources :cases, only: [:new, :create]
    end
    resources :cases, only: [:index, :show, :new, :create] do
      member do
        post :add_note
        post :escalate
      end
    end

    get  "customer_manager", to: "customer_manager#index"
    post "customer_manager", to: "customer_manager#create"

    resources :audit_logs, only: [:index]

    namespace :admin do
      resource :view_as, only: [:create, :destroy], controller: "view_as"
    end
  end

  devise_scope :user do
    unauthenticated do
      root to: "devise/sessions#new", as: :unauthenticated_root
    end
  end
end
