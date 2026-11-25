# frozen_string_literal: true

# Production boot checks with dummy ENV and an unreachable local database.
# This script must not connect to a customer database or any remote service.
require "minitest/autorun"
abort "Use production with the dummy runtime check URL" unless Rails.env.production? && ENV["DATABASE_URL"] == "postgresql://127.0.0.1:1/emvi_runtime_check"

class Upgrade031RuntimeTest < Minitest::Test
  def test_mailer_env_values_and_boolean_starttls
    settings = Rails.application.config.action_mailer.smtp_settings
    expected = Integer(ENV.fetch("SMTP_READ_TIMEOUT", "15"), 10)
    assert_equal expected, settings[:read_timeout]
    assert_equal expected, ActionMailer::Base.smtp_settings[:read_timeout]
    # Construct transport only; never start/connect/send.
    smtp = Mail::SMTP.new(ActionMailer::Base.smtp_settings).send(:build_smtp_session)
    assert_equal expected, smtp.read_timeout
    assert_equal "smtp.example.org", settings[:address]
    assert_equal 2525, settings[:port]
    assert_equal "plain", settings[:authentication]
    assert_equal "runtime-user", settings[:user_name]
    assert_equal "runtime-password", settings[:password]
    assert_equal "example.org", settings[:domain]
    assert_equal(ENV["SMTP_STARTTLS_AUTO"] != "false", settings[:enable_starttls_auto])
  end

  def test_redis_and_job_configuration
    assert_equal :good_job, Rails.application.config.active_job.queue_adapter
    kind, settings = Rails.application.config.cache_store
    assert_equal :redis_cache_store, kind
    assert_equal "redis://myMaster/0", settings[:url]
    assert_equal %w(redis-cache-sentinel redis-cache-sentinel-additional), settings[:sentinels].map { |entry| entry[:host] }
    assert_equal "redis://myMaster/0", ActionCable.server.config.cable.fetch("url")
    assert_equal %w(redis-sentinel redis-sentinel-additional), ActionCable.server.config.cable.fetch("sentinels").map { |entry| entry.fetch("host") }
  end

  def test_minio_signed_path_style_url_without_network_or_upload
    assert_equal :minio, Rails.application.config.active_storage.service
    configuration = Rails.application.config.active_storage.service_configurations.fetch("minio")
    refute configuration.fetch("public", false)
    assert configuration.fetch("force_path_style")
    service = ActiveStorage::Service.configure(:minio, { "minio" => configuration })
    url = URI.parse(service.url("synthetic-proof", expires_in: 5.minutes, filename: ActiveStorage::Filename.new("probe.txt"), content_type: "text/plain", disposition: :inline))
    assert_equal "storage.example.org", url.host
    assert_equal "/runtime-bucket/synthetic-proof", url.path
    assert URI.decode_www_form(url.query).to_h.key?("X-Amz-Signature")
  end

  def test_image_magick_security_policy_is_loaded
    policy_directory = Rails.root.join("config/image_magick").to_s
    assert_equal policy_directory, ENV.fetch("MAGICK_CONFIGURE_PATH").split(File::PATH_SEPARATOR).first
    policy = File.read(File.join(policy_directory, "policy.xml"))
    assert_includes policy, 'domain="coder" rights="none" pattern="MSL"'
    assert_includes policy, 'domain="path" rights="none" pattern="@*"'
  end

  def test_development_proxy_is_absent_in_production
    assert_nil Shakapacker.config.dev_server
    refute_includes Rails.application.middleware.map { |entry| entry.klass.name }, "Shakapacker::DevServerProxy"
  end

  def test_here_and_machine_translation_settings
    assert_equal "here", Decidim.maps.fetch(:provider).to_s
    assert_equal "https://image.maps.hereapi.com/mia/v3/base/mc/overlay", Decidim.maps.dig(:static, :url)
    assert_equal "runtime-map-key", Decidim.maps.fetch(:api_key)
    assert_equal(ENV["DECIDIM_ENABLE_MACHINE_TRANSLATION"] != "false", Decidim.enable_machine_translations)
    assert_equal "Decidim::AmazonTranslate::AmazonTranslator", Decidim.machine_translation_service
    assert_equal "de", Decidim.default_locale.to_s
  end
end
