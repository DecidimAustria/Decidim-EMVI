# frozen_string_literal: true

source "https://rubygems.org"

ruby RUBY_VERSION
DECIDIM_VERSION = "0.27.2"

#gem "decidim", DECIDIM_VERSION
gem "decidim", git: "https://github.com/DecidimAustria/decidim", branch: 'emvi-0.27.2'
gem "decidim-alternative_landing", git: "https://github.com/DecidimAustria/decidim-module-alternative_landing", branch: 'update-to-decidim-0.27'
#gem "decidim-decidim_awesome", git: "https://github.com/DecidimAustria/decidim-module-decidim_awesome", branch: 'update-to-decidim-0.27'
gem "decidim-decidim_awesome", git: "https://github.com/DecidimAustria/decidim-module-decidim_awesome", branch: 'update-to-decidim-0.27', :ref => 'df40b3691a64a2'
# gem "decidim-conferences", DECIDIM_VERSION
gem "decidim-consultations", git: "https://github.com/DecidimAustria/decidim", branch: 'emvi-0.27.2'
# gem "decidim-elections", DECIDIM_VERSION
# gem "decidim-initiatives", DECIDIM_VERSION
# gem "decidim-templates", DECIDIM_VERSION

# Get latest CLDR changes to fix bug with count :zero
# remove when this commit gets released in a version https://github.com/ruby-i18n/i18n/commit/c78ca610b64712037e5726adeaf7b84fa96eded9
gem "i18n", git: "https://github.com/ruby-i18n/i18n", branch: "master"

gem "aws-sdk-translate", '~> 1'

#gem "deepl-rb", require: "deepl"

gem "bootsnap", "~> 1.3"

gem "puma", ">= 5.0.0"

gem "faker", "~> 2.14"

gem "sentry-ruby"
gem "sentry-rails"

gem 'sidekiq', '<7'
gem 'virtus', '~> 1.0.5'
gem "wicked_pdf", "~> 2.1"

gem "rectify", "~> 0.13.0"

group :development, :test do
  gem "byebug", "~> 11.0", platform: :mri

  gem "brakeman"
  gem "net-imap", "~> 0.2.3"
  gem "net-pop", "~> 0.1.1"
  gem "net-smtp", "~> 0.3.1"
  gem "decidim-dev", git: "https://github.com/DecidimAustria/decidim", branch: 'emvi-0.27.2'
end

group :development do
  gem "easy_translate", "~> 0.5.1"
  gem "letter_opener_web", "~> 2.0"
  gem "listen", "~> 3.1"
  gem "solargraph"
  gem "spring", "~> 2.0"
  gem "spring-watcher-listen", "~> 2.0.0"
  gem "web-console", "~> 4.2"
end

group :production do
end
