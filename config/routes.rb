Rails.application.routes.draw do
  root "projects#index"

  resources :projects do
    resources :repositories, only: [:index, :show, :create, :destroy]
    resources :developers, only: [:index, :show, :update] do
      collection do
        get :export
      end
    end
  end
end
