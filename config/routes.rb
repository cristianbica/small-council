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

  resources :councils do
    resources :advisors, only: [ :new, :create, :edit, :update, :destroy ]
    resources :conversations, only: [ :index, :show, :new, :create, :update ]
  end

  resources :conversations do
    resources :messages, only: [ :create ]
  end

  # Health check
  get "up" => "rails/health#show", as: :rails_health_check

  # Root - redirect to dashboard (which requires auth, so will redirect to sign_in if not logged in)
  root "dashboard#index"
end
