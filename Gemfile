# frozen_string_literal: true

source "https://rubygems.org"

ruby '3.1.5'
# DECIDIM_VERSION = { git: "https://github.com/DecidimAustria/decidim", branch: '0.28-live' }
DECIDIM_VERSION = { git: "https://github.com/DecidimAustria/decidim", branch: '0.28.4-live' }
# DECIDIM_VERSION = "0.28.4"

gem "decidim", DECIDIM_VERSION
#gem "decidim-alternative_landing", git: "https://github.com/DecidimAustria/decidim-module-alternative_landing", branch: 'update-to-decidim-0.27'
# alternative_landing was disabled because it is not compatible with decidim 0.29
# gem "decidim-alternative_landing", git: "https://github.com/Platoniq/decidim-module-alternative_landing.git", branch: 'release/0.27-stable'
#gem "decidim-decidim_awesome", git: "https://github.com/DecidimAustria/decidim-module-decidim_awesome", branch: 'update-to-decidim-0.27'
#gem "decidim-decidim_awesome", git: "https://github.com/DecidimAustria/decidim-module-decidim_awesome", branch: 'update-to-decidim-0.27', :ref => 'df40b3691a64a2'
gem "decidim-decidim_awesome", "~> 0.11.2"
# gem "decidim-conferences", DECIDIM_VERSION
# consultations does not exist from 0.28
# gem "decidim-consultations", DECIDIM_VERSION
# gem "decidim-elections", DECIDIM_VERSION
# gem "decidim-initiatives", DECIDIM_VERSION
# gem "decidim-templates", DECIDIM_VERSION
# gem "decidim-term_customizer", git: "https://github.com/mainio/decidim-module-term_customizer", branch: "main"
gem "decidim-amazon_translate"

# Get latest CLDR changes to fix bug with count :zero
# remove when this commit gets released in a version https://github.com/ruby-i18n/i18n/commit/c78ca610b64712037e5726adeaf7b84fa96eded9
gem "i18n", git: "https://github.com/ruby-i18n/i18n", branch: "master"

gem "aws-sdk-translate", '~> 1'
gem 'aws-sdk-s3'

#gem "deepl-rb", require: "deepl"

gem "bootsnap", "~> 1.3"

gem "puma", ">= 5.0.0"

gem "faker", "~> 3.2"

gem 'hiredis'
gem "redis", :require => ["redis", "redis/connection/hiredis"]

gem 'stackprof'
gem "sentry-ruby"
gem "sentry-rails"

gem 'virtus', '~> 1.0.5'
gem "wicked_pdf", "~> 2.1"

gem "rectify", "~> 0.13.0"

group :development, :test do
  gem "byebug", "~> 11.0", platform: :mri

  gem "brakeman"
  gem "net-imap", "~> 0.2.3"
  gem "net-pop", "~> 0.1.1"
  gem "net-smtp", "~> 0.3.1"
  gem "decidim-dev", DECIDIM_VERSION
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

gem "good_job", "~> 3.25"
