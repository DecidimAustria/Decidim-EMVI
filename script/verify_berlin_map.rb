# frozen_string_literal: true

# Rails runner in test mode against the isolated synthetic rehearsal database.
# BERLIN_LEGACY_FIXTURE points to the authorized, private export of block 63.
require "minitest/autorun"
require "tmpdir"
require "json"

config = ActiveRecord::Base.connection_db_config.configuration_hash
abort "Use only the synthetic rehearsal DB" unless Rails.env.test? && config[:database] == "emvi_030_data_rehearsal" && config[:host] == "/private/tmp/decidim-0297-pg/socket"
LEGACY_BERLIN_CONTENT = JSON.parse(File.read(ENV.fetch("BERLIN_LEGACY_FIXTURE"))).fetch("content")

class BerlinMapTest < Minitest::Test
  def setup
    ActiveRecord::Base.connection.begin_transaction(joinable: false)
    @organization = Decidim::Organization.order(:id).first
    @organization.update_columns(host: Emvi::BerlinDistrictMap::HOST, available_locales: LEGACY_BERLIN_CONTENT.keys, default_locale: "de")
    @other = Decidim::Organization.where.not(id: @organization.id).first
    @block = Decidim::ContentBlock.create!(organization: @organization, scope_name: "homepage", manifest_name: "html", weight: 42, published_at: Time.current.change(usec: 0), settings: { "html_content" => LEGACY_BERLIN_CONTENT })
    @directory = Dir.mktmpdir("berlin-map-test-")
    @backup = File.join(@directory, "backup.json")
    RequestStore.store[:toggle_machine_translations] = false
  end

  def teardown
    ActiveRecord::Base.connection.rollback_transaction
    FileUtils.remove_entry(@directory) if @directory
    RequestStore.store[:toggle_machine_translations] = nil
  end

  def convert
    Emvi::BerlinMapConversion.apply!(@block, @backup)
    Decidim::ContentBlock.find(@block.id)
  end

  def render_block(block, organization = @organization, locale = :de)
    controller = Decidim::ApplicationController.new
    controller.set_request!(ActionDispatch::Request.new(Rack::MockRequest.env_for("https://#{organization.host}/")))
    controller.define_singleton_method(:current_organization) { organization }
    I18n.with_locale(locale) do
      Cell::ViewModel.cell("emvi/berlin_district_map", block, context: { controller: controller }).call.to_s
    end
  end

  def test_conversion_preserves_all_translations_position_and_publication
    original = @block.attributes
    converted = convert
    assert_equal "berlin_district_map", converted.manifest_name
    assert_equal original["weight"], converted.weight
    assert_equal original["published_at"], converted.published_at
    assert_equal LEGACY_BERLIN_CONTENT.keys.sort, converted.settings.title.keys.sort
    LEGACY_BERLIN_CONTENT.each do |locale, html|
      old = Nokogiri::HTML5.fragment(html)
      assert_equal old.at_css("h1").text.strip, converted.settings.title.fetch(locale)
      assert_equal old.at_css(".berlinCard > p").inner_html.strip, converted.settings.introduction.fetch(locale)
    end
    assert_equal 0o600, File.stat(@backup).mode & 0o777
    assert_equal original["settings"], JSON.parse(File.read(@backup)).dig("original", "settings")
  end

  def test_renders_map_links_and_correct_language_for_every_locale
    converted = convert
    LEGACY_BERLIN_CONTENT.keys.each do |locale|
      html = render_block(converted, @organization, locale)
      doc = Nokogiri::HTML5.fragment(html)
      assert_equal converted.settings.title.fetch(locale), doc.at_css("h2").text
      assert_equal 13, doc.css("svg#berlinCard a[href^='/assemblies/']").length
      assert_equal 12, doc.css(".districtList li a").length
      assert_equal 1, doc.css("link[href='/berlin-district-map/map-v2.css']").length
      assert_empty doc.css("script")
      assert_empty doc.css("style, dialog")
      refute_includes doc.text, "position: relative"
    end
    if ENV["BERLIN_MAP_PREVIEW_DIR"]
      destination = Pathname.new(ENV.fetch("BERLIN_MAP_PREVIEW_DIR"))
      FileUtils.mkdir_p(destination.join("berlin-district-map"))
      FileUtils.cp(Rails.root.glob("public/berlin-district-map/*"), destination.join("berlin-district-map"))
      html = '<!doctype html><html lang="de"><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><style>body{font-family:sans-serif;--primary-rgb:40 70 110;margin:2rem}section{max-width:1100px;margin:auto}h2{text-align:center}</style>' + render_block(converted) + '</html>'
      destination.join("index.html").write(html)
    end
  end

  def test_other_organizations_and_mismatched_block_load_no_assets
    assert_equal "", render_block(@block)
    converted = convert
    assert_equal "", render_block(converted, @other)
    converted.organization = @other
    assert_equal "", render_block(converted)
    other_block = Decidim::ContentBlock.create!(organization: @other, scope_name: "homepage", manifest_name: "html", settings: { "html_content" => LEGACY_BERLIN_CONTENT })
    assert_raises(RuntimeError) { Emvi::BerlinMapConversion.apply!(other_block, @backup) }
  end

  def test_admin_creation_and_menu_are_restricted
    manifests = Decidim.content_blocks.for(:homepage)
    base = Class.new do
      define_method(:available_manifests) { manifests }
    end
    view = Class.new(base) do
      prepend Emvi::BerlinDistrictMap::HomepageManifests
      attr_accessor :current_organization
    end.new
    view.current_organization = @other
    refute_includes view.send(:available_manifests).map(&:name), :berlin_district_map
    view.current_organization = @organization
    assert_includes view.send(:available_manifests).map(&:name), :berlin_district_map
    result = nil
    Decidim::Admin::ContentBlocks::CreateContentBlock.call(@other, :homepage, :berlin_district_map) { on(:invalid) { result = :invalid } }
    assert_equal :invalid, result
  end

  def test_user_text_is_escaped_and_sanitized
    block = convert
    block[:settings] = { "title" => { "de" => '<script>alert("title")</script>' }, "introduction" => { "de" => '<p onclick="evil()">Hallo</p><script>alert("body")</script>' } }
    doc = Nokogiri::HTML5.fragment(render_block(block))
    assert_equal '<script>alert("title")</script>', doc.at_css("h2").text
    assert_empty doc.css("script:not([src]), [onclick]")
    assert_includes doc.text, "Hallo"
  end

  def test_restore_is_exact_and_rejects_later_edits
    original = @block.attributes.slice("manifest_name", "settings", "weight", "published_at")
    converted = convert
    Emvi::BerlinMapConversion.restore!(@backup)
    assert_equal original, Decidim::ContentBlock.find(@block.id).attributes.slice(*original.keys)
    assert_raises(RuntimeError) { Emvi::BerlinMapConversion.restore!(@backup) }
    File.unlink(@backup)
    converted = convert
    converted.update!(settings: converted[:settings].deep_merge("title" => { "de" => "Edited later" }))
    assert_raises(RuntimeError) { Emvi::BerlinMapConversion.restore!(@backup) }
  end

  def test_maintenance_preview_does_not_write
    Rails.application.load_tasks unless Rake::Task.task_defined?("emvi:berlin_map:convert")
    old = ENV.to_h.slice("BLOCK_ID", "APPLY", "BACKUP_PATH")
    ENV["BLOCK_ID"] = @block.id.to_s
    ENV.delete("APPLY")
    task = Rake::Task["emvi:berlin_map:convert"]
    task.reenable
    output, = capture_io { task.invoke }
    assert_includes output, '"preview"'
    assert_equal "html", @block.reload.manifest_name
    refute File.exist?(@backup)
  ensure
    %w[BLOCK_ID APPLY BACKUP_PATH].each { |key| old.key?(key) ? ENV[key] = old[key] : ENV.delete(key) }
  end

  def test_unreviewed_markup_and_existing_backup_abort_before_changes
    changed = LEGACY_BERLIN_CONTENT.deep_dup
    changed["de"] = changed["de"].sub(".berlinCard {", ".unreviewed {")
    assert_raises(RuntimeError) { Emvi::BerlinMapConversion.convert(changed) }
    File.write(@backup, "existing")
    assert_raises(Errno::EEXIST) { Emvi::BerlinMapConversion.apply!(@block, @backup) }
    assert_equal "html", @block.reload.manifest_name
    assert_equal "existing", File.read(@backup)
  end
end
