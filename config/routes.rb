Rails.application.routes.draw do
  if Rails.env.development?
    mount LetterOpenerWeb::Engine, at: "/letter_opener"
  end

  authenticate :user, ->(user) { user.admin? } do
    mount GoodJob::Engine => 'good_job'
  end

  mount Decidim::Core::Engine => '/'
  # For details on the DSL available within this file, see https://guides.rubyonrails.org/routing.html
end
