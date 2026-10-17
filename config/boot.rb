ENV['BUNDLE_GEMFILE'] ||= File.expand_path('../Gemfile', __dir__)

# Use the npm lockfile without relying on buildpack-provided environment variables.
ENV["SHAKAPACKER_USE_PACKAGE_JSON_GEM"] ||= "true"
ENV["PACKAGE_JSON_FALLBACK_MANAGER"] ||= "npm"

require "bundler/setup" # Set up gems listed in the Gemfile.
require "bootsnap/setup" # Speed up boot time by caching expensive operations.
