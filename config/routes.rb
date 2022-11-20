require "sidekiq/web"

Rails.application.routes.draw do
  if Rails.env.development?
    mount LetterOpenerWeb::Engine, at: "/letter_opener"
  end

  Rails.application.routes.draw do
    authenticate :user, ->(u) { u.admin? } do
      mount Sidekiq::Web => "/sidekiq"
    end
  end

  mount Decidim::Core::Engine => '/'
  # For details on the DSL available within this file, see https://guides.rubyonrails.org/routing.html
end
