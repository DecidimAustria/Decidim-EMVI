# frozen_string_literal: true

# Rails runner, no database access. Set WRITE_LOCALE_FIXES=1 to persist reviewed
# 0.30.9 interpolation repairs; otherwise this reports the necessary corrections.
require "json"
require "yaml"
require "nokogiri"
abort "Only reviewed for Decidim 0.30.9" unless Decidim.version == "0.30.9"

contracts = {
  "decidim.admin.imports.notice" => %w[count resource_name],
  "decidim.debates.actions.new" => [],
  "decidim.admin.organization_appearance.form.colors.colors_warning_html" => [],
  "decidim.components.add_comment_form.account_message" => [],
  "decidim.meetings.close_meeting_reminder_mailer.close_meeting_reminder.subject" => %w[meeting_title],
  "decidim.meetings.registration_mailer.confirmation.confirmed_html" => %w[title url],
  "decidim.proposals.admin.proposals_imports.create.success" => [],
  "decidim.sortitions.sortitions.show.candidate_proposals_info" => %w[taxonomy_labels]
}
%w[highlighted_meetings highlighted_results highlighted_proposals].each do |block|
  contracts["decidim.participatory_spaces.#{block}.see_all"] = []
end
%w[email_intro email_outro email_subject notification_title].each do |part|
  contracts["decidim.events.debates.create_debate_event.space_followers.#{part}"] = %w[resource_title resource_path resource_url participatory_space_title participatory_space_url author_name author_nickname author_path author_url]
end
%w[invalid success].each do |status|
  %w[selected unselected].each do |action|
    contracts["decidim.budgets.admin.projects.update_selected.#{status}.#{action}"] = %w[successful errored]
  end
end
import_success = {
  "ar-SA" => "تم استيراد المقترحات بنجاح.",
  "bs" => "Prijedlozi su uspješno uvezeni.", "hr" => "Prijedlozi su uspješno uvezeni.",
  "sr-CS" => "Prijedlozi su uspješno uvezeni.", "sl" => "Predlogi so bili uspešno uvoženi.",
  "fa-IR" => "پیشنهادها با موفقیت وارد شدند.", "uk" => "Пропозиції успішно імпортовано."
}
locales = %w[bs ca cs de en es fr hr it nl pl pt ro ru el sl sr-CS tr-TR ar-SA fa-IR uk zh-TW].sort
missing_locales = locales - Decidim.available_locales.map(&:to_s)
abort "Set DECIDIM_AVAILABLE_LOCALES before Rails boot to all EMVI locales: #{missing_locales.join(",")}" if missing_locales.any?
file = Rails.root.join("config/locales/zz.emvi_030_compatibility.yml")
repairs = file.exist? ? YAML.safe_load(file.read, aliases: true) : {}
changes = []
locales.each do |locale|
  contracts.each do |key, allowed|
    value = I18n.t(key, locale: locale, default: nil)
    next unless value.is_a?(String)
    extra = value.scan(/%\{([^}]+)\}/).flatten.uniq - allowed
    next if extra.empty?

    fixed = value.dup
    if key == "decidim.admin.imports.notice"
      fixed.gsub!("%{number}", "%{count}")
    elsif key.start_with?("decidim.events.debates.create_debate_event.")
      fixed.gsub!("%{space_title}", "%{participatory_space_title}")
      fixed.gsub!("%{space_path}", "%{participatory_space_url}")
    elsif key.start_with?("decidim.budgets.admin.projects.update_selected.")
      replacement = key.include?(".invalid.") ? "errored" : "successful"
      fixed.gsub!("%{projects}", "%{#{replacement}}")
    elsif key == "decidim.sortitions.sortitions.show.candidate_proposals_info"
      fixed.gsub!("%{category_label}", "%{taxonomy_labels}")
    elsif key == "decidim.meetings.registration_mailer.confirmation.confirmed_html"
      fixed.gsub!("%{resource_title}", "%{title}")
      fixed.gsub!("%{resource_url}", "%{url}")
    elsif key == "decidim.admin.organization_appearance.form.colors.colors_warning_html"
      # Same fixed destination supplied by the original 0.27 view.
      fixed.gsub!("%{link}", "https://webaim.org/resources/contrastchecker")
    elsif key == "decidim.components.add_comment_form.account_message"
      # 0.30 wraps this text in the onboarding link; avoid nested old login links.
      anchor = Nokogiri::HTML.fragment(value).at_css("a")
      fixed = anchor.text.strip if anchor
    elsif key == "decidim.debates.actions.new"
      fixed = I18n.t("decidim.debates.debates.new.title", locale: locale, default: "New debate")
    elsif key == "decidim.meetings.close_meeting_reminder_mailer.close_meeting_reminder.subject"
      # Reuse the existing translated action instead of naming a meeting as an organization.
      label = I18n.t("decidim.meetings.meeting_closes.edit.close", locale: locale, default: "Close meeting")
      fixed = "#{label}: %{meeting_title}"
    elsif key == "decidim.proposals.admin.proposals_imports.create.success"
      fixed = import_success.fetch(locale, "Proposals successfully imported.")
    elsif key.match?(/\.highlighted_(meetings|results|proposals)\.see_all\z/)
      fixed.gsub!(/\s*\(%\{count\}\)/, "")
    end
    remaining = fixed.scan(/%\{([^}]+)\}/).flatten.uniq - allowed
    abort "Unreviewed interpolation #{locale}.#{key}: #{remaining.inspect}" unless remaining.empty?
    target = key.split(".")[0...-1].reduce(repairs[locale] ||= {}) { |hash, part| hash[part] ||= {} }
    target[key.split(".").last] = fixed
    changes << { locale: locale, key: key, removed_parameters: extra }
  end
end
# Upstream 0.30.9 accidentally contains Romanian text in the German locale.
# Removing the stock 0.27 override exposes it, although its interpolation is valid.
key = "decidim.pages.home.statistics.headline"
fixed = "Aktueller Zustand von %{organization}"
unless I18n.t(key, locale: :de) == fixed
  target = key.split(".")[0...-1].reduce(repairs["de"] ||= {}) { |hash, part| hash[part] ||= {} }
  target[key.split(".").last] = fixed
  changes << { locale: "de", key: key, reason: "Romanian text in upstream German locale" }
end
if ENV["WRITE_LOCALE_FIXES"] == "1" && changes.any?
  serialized = YAML.dump(repairs.sort.to_h, line_width: -1)
  abort "YAML roundtrip failed" unless YAML.safe_load(serialized, aliases: true) == repairs
  file.write(serialized)
end
puts JSON.pretty_generate(corrections: changes.length, by_locale: changes.group_by { |c| c[:locale] }.transform_values(&:length), changes: changes)
