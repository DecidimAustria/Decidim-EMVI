# frozen_string_literal: true

# Rails runner with the full DECIDIM_AVAILABLE_LOCALES from projects_tf.
# Uses no database, HTTP, mail delivery or uploads.
require "minitest/autorun"
require "yaml"
require "date"
require "open3"
require "stringio"
require "rubygems/package"
require "json"

module EmviLocaleAudit
  BASELINE = "3aa32dcb21f9043488fe7d1def91b26f592b455c"
  LOCALES = %w[bs ca cs de en es fr hr it nl pl pt ro ru el sl sr-CS tr-TR ar-SA fa-IR uk zh-TW].freeze
  EDITORIAL_KEYS = %w[
    de.activemodel.attributes.assembly.parent_id
    de.activerecord.models.decidim/assembly_member.one
    de.decidim.admin.assemblies.new.title
    de.decidim.admin_log.assembly.duplicate
    de.decidim.assemblies.assemblies.show.title
    de.layouts.decidim.assemblies.order_by_assemblies.assemblies.one
    de.decidim.devise.shared.newsletter_modal.notice
  ].freeze

  def self.parse(raw)
    YAML.safe_load(raw, permitted_classes: [Date, Time, Symbol], aliases: true) || {}
  end

  def self.flatten(value, path = [], result = {})
    if value.is_a?(Hash)
      value.each { |key, item| flatten(item, path + [key.to_s], result) }
    else
      result[path.join(".")] = value
    end
    result
  end

  def self.archive(repo, ref, paths)
    raw, error, status = Open3.capture3("git", "-C", repo.to_s, "archive", ref, "--", *paths, binmode: true)
    abort error unless status.success?
    result = {}
    Gem::Package::TarReader.new(StringIO.new(raw)) do |tar|
      tar.each { |entry| result[entry.full_name] = parse(entry.read) if entry.file? && entry.full_name.end_with?(".yml", ".yaml") }
    end
    result
  end

  BEFORE = archive(Rails.root, BASELINE, ["config/locales"]).transform_values { |data| flatten(data) }
  AFTER = Rails.root.glob("config/locales/*.{yml,yaml}").to_h { |file| [file.relative_path_from(Rails.root).to_s, flatten(parse(file.read))] }
  STOCK = Hash.new { |hash, key| hash[key] = [] }
  upstream = ENV.fetch("UPSTREAM_DECIDIM_CHECKOUT", Rails.root.join("../decidim").to_s)
  %w[v0.27.0 v0.27.1 v0.27.2].each do |ref|
    names, status = Open3.capture2("git", "-C", upstream, "ls-tree", "-r", "--name-only", ref)
    abort "Missing official tag #{ref}" unless status.success?
    paths = names.lines.map(&:strip).grep(%r{\Adecidim-[^/]+/config/locales/[^/]+\.yml\z})
    archive(upstream, ref, paths).each_value do |data|
      flatten(data).each { |key, value| STOCK[key] << value unless STOCK[key].include?(value) }
    end
  end
end

abort "Boot Rails with every EMVI locale configured" unless (EmviLocaleAudit::LOCALES - Decidim.available_locales.map(&:to_s)).empty?

class EmviLocaleCleanupTest < Minitest::Test
  A = EmviLocaleAudit

  def test_only_identical_historical_stock_values_were_removed
    removed = 0
    A::BEFORE.each do |file, values|
      current = A::AFTER.fetch(file, {})
      values.each do |key, value|
        if current.key?(key)
          assert_equal value, current[key], "Unexpected custom change: #{file}:#{key}" unless A::EDITORIAL_KEYS.include?(key)
        else
          locale, suffix = key.split(".", 2)
          sources = [locale, locale.split("-").first].uniq
          assert value.is_a?(String) && sources.any? { |source| A::STOCK[source + "." + suffix].include?(value) }, "Non-stock value removed: #{file}:#{key}"
          removed += 1
        end
      end
    end
    assert_operator removed, :>, 45_000
  end

  def test_all_yaml_keeps_its_types_after_serialization
    Rails.root.glob("config/locales/*.{yml,yaml}").each do |file|
      data = A.parse(file.read)
      assert_equal data, A.parse(YAML.dump(data, line_width: -1)), file.to_s
    end
  end

  def test_emvi_text_and_elected_member_labels_are_preserved
    protected = 0
    A::BEFORE.each do |file, values|
      values.each do |key, value|
        next unless key.include?(".emvi.") || key.match?(/\.assembly_member\.positions\.(president|vice_president|secretary)\z/)

        locale, suffix = key.split(".", 2)
        copied_stock_role = !key.include?(".emvi.") && [locale, locale.split("-").first].uniq.any? { |name| A::STOCK[name + "." + suffix].include?(value) }
        next if copied_stock_role

        assert_equal value, A::AFTER.fetch(file).fetch(key), key
        protected += 1
      end
    end
    assert_operator protected, :>, 30
    file = "config/locales/pl.terms_of_service.yml"
    assert_equal A::BEFORE.fetch(file), A::AFTER.fetch(file)
  end

  def assert_rendered(key, args)
    A::LOCALES.each do |locale|
      value = I18n.t(key, locale: locale, **args, default: nil)
      assert_kind_of String, value, "#{locale}.#{key}"
      refute_match(/%\{[^}]+\}/, value, "#{locale}.#{key}")
    end
  end

  def test_current_ui_interpolation_calls
    assert_rendered("decidim.admin.imports.notice", count: 3, resource_name: "items")
    assert_rendered("decidim.debates.actions.new", {})
    assert_rendered("decidim.admin.organization_appearance.form.colors.colors_warning_html", {})
    assert_rendered("decidim.meetings.close_meeting_reminder_mailer.close_meeting_reminder.subject", meeting_title: "Example meeting")
    assert_rendered("decidim.meetings.registration_mailer.confirmation.confirmed_html", title: "Example meeting", url: "https://example.org/meeting")
    assert_rendered("decidim.proposals.admin.proposals_imports.create.success", {})
    assert_rendered("decidim.sortitions.sortitions.show.candidate_proposals_info", taxonomy_labels: "Example taxonomy")
    %w[highlighted_meetings highlighted_results highlighted_proposals].each do |block|
      assert_rendered("decidim.participatory_spaces.#{block}.see_all", {})
    end
    %w[invalid success].each do |status|
      %w[selected unselected].each do |action|
        assert_rendered("decidim.budgets.admin.projects.update_selected.#{status}.#{action}", successful: "Project A", errored: "Project B")
      end
    end
  end

  def test_debate_event_interpolations
    args = { resource_path: "/debates/1", resource_url: "https://example.org/debates/1", resource_title: "Example debate", participatory_space_title: "Example space", participatory_space_url: "https://example.org/processes/example", author_name: "Example author", author_nickname: "example", author_path: "/profiles/example", author_url: "https://example.org/profiles/example" }
    %w[email_intro email_outro email_subject notification_title].each do |part|
      assert_rendered("decidim.events.debates.create_debate_event.space_followers.#{part}", args)
    end
  end

  def test_onboarding_label_has_no_nested_legacy_login_links
    A::LOCALES.each do |locale|
      value = I18n.t("decidim.components.add_comment_form.account_message", locale: locale)
      refute_match(/%\{|<a\b/i, value, locale)
    end
  end

  def test_german_homepage_statistics_heading
    assert_equal "Aktueller Zustand von graz", I18n.t("decidim.pages.home.statistics.headline", locale: :de, organization: "graz")
  end

  def test_polish_terms_and_german_editorial_corrections
    assert_includes I18n.t("decidim.pages.terms_of_service.refuse.modal_body", locale: :pl, download_your_data_path: "/download-data", delete_path: "/delete-account"), 'href="/download-data"'
    assert_equal "Neue Organisation", I18n.t("decidim.admin.assemblies.new.title", locale: :de)
    assert_equal "Übergeordnete Organisation", I18n.t("activemodel.attributes.assembly.parent_id", locale: :de)
    assert_equal "Organisationsmitglied", I18n.t("activerecord.models.decidim/assembly_member.one", locale: :de)
  end
end
