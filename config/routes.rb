Rails.application.routes.draw do
  root "dashboard#index"

  resources :repositories, only: [:index, :show, :create]
  resources :developers, only: [:index, :show, :update]
end
