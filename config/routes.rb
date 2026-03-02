Rails.application.routes.draw do
  # Authentication routes
  get  "sign_in", to: "sessions#new"
  post "sign_in", to: "sessions#create"
  get  "sign_up", to: "registrations#new"
  post "sign_up", to: "registrations#create"
  resources :sessions, only: [ :index, :show, :destroy ]
  resource  :password, only: [ :edit, :update ]
  namespace :identity do
    resource :email,              only: [ :edit, :update ]
    resource :email_verification, only: [ :show, :create ]
    resource :password_reset,     only: [ :new, :edit, :create, :update ]
  end

  # Protected app routes
  get "dashboard", to: "dashboard#index"

  # Settings
  resource :settings, only: [ :edit, :update ]

  # Spaces routes with nested councils, advisors, memories, and scribe
  resources :spaces do
    resources :councils, only: [ :index, :new, :create ]
    resources :advisors do
      collection do
        post :generate_prompt
      end
    end
    resources :memories do
      member do
        post :archive
        post :activate
        get :versions
        get :version
        post :restore_version
      end
      collection do
        get :search
        get :export
      end
    end
  end

  # Councils can still be accessed directly (redirects to current space context)
  resources :councils do
    resources :advisors, only: [ :new, :create, :edit, :update, :destroy ] do
      collection do
        post :generate_prompt
        get :select
        post :add_existing
      end
    end
    resources :conversations, only: [ :index, :show, :new, :create, :update, :destroy ]

    collection do
      post :generate_description
    end

    member do
      post :generate_description
    end
  end

  resources :conversations do
    resources :messages, only: [ :create ]
    member do
      post :finish
      post :archive
      post :invite_advisor
    end

    collection do
      post :quick_create
    end
  end

  resources :providers do
    collection do
      get :wizard
      post :wizard_step
      post :wizard_back
      post :wizard_cancel
      post :test_connection
      get :models
      post :toggle_model
    end

    member do
      get :models
    end
  end

  # Health check
  get "up" => "rails/health#show", as: :rails_health_check

  # Root - redirect to dashboard (which requires auth, so will redirect to sign_in if not logged in)
  root "dashboard#index"
end
