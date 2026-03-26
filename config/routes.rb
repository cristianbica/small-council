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
  resource :form_filler, only: [ :new, :create ]

  # Spaces routes with nested councils, advisors, memories, and scribe
  resources :spaces do
    resources :councils, only: [ :index, :new, :create ]
    resources :advisors
      resources :memories do
      member do
        post :archive
        post :activate
        get :versions
        get :version
        post :restore_version
        get :export
      end
      collection do
        get :search
      end
    end
  end

  # Councils can still be accessed directly (redirects to current space context)
  resources :councils do
    member do
      get :edit_advisors
      patch :update_advisors
    end
    resources :conversations, only: [ :index, :show, :new, :create, :update, :destroy ]
  end

  resources :conversations do
    resources :messages, only: [ :create ] do
      member do
        get :interactions
        post :retry
      end
    end
    resources :conversation_participants, path: "participants", only: [ :edit, :update ]
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
