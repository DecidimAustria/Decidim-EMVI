# frozen_string_literal: true

require "json"
require "digest"

module Emvi
  class BerlinMapConversion
    def self.convert(content)
      fingerprints = JSON.parse(Rails.root.join("config/berlin_map_legacy_fingerprints.json").read)
      settings = { "title" => {}, "introduction" => {} }
      content.each do |locale, html|
        next if html.blank?

        document = Nokogiri::HTML5.fragment(html)
        title = document.at_css("h1") or raise "Missing heading for #{locale}"
        introduction = document.at_css(".berlinCard > p") or raise "Missing introduction for #{locale}"
        settings["title"][locale] = title.text.strip
        settings["introduction"][locale] = introduction.inner_html.strip
        skeleton = document.dup
        skeleton.at_css("h1").inner_html = "TITLE"
        skeleton.at_css(".berlinCard > p").inner_html = "INTRODUCTION"
        actual = {
          "layout" => Digest::SHA256.hexdigest(skeleton.to_html),
          "style" => document.css("style").map { |n| Digest::SHA256.hexdigest(n.text) },
          "script" => document.css("script").map { |n| Digest::SHA256.hexdigest(n.text) },
          "svg" => document.css("svg").map { |n| Digest::SHA256.hexdigest(n.to_html) }
        }
        raise "Unreviewed markup for #{locale}; review before conversion" unless fingerprints[locale] == actual
      end
      raise "No translated content" if settings["title"].empty?

      settings
    end

    def self.digest(settings)
      # JSONB keys may be reordered by PostgreSQL.
      canonical = ->(value) { value.is_a?(Hash) ? value.sort.to_h.transform_values { |v| canonical.call(v) } : value }
      Digest::SHA256.hexdigest(JSON.generate(canonical.call(settings)))
    end

    def self.guard!(block)
      raise "Not the Berlin homepage" unless BerlinDistrictMap.organization?(block.organization) && block.scope_name == "homepage" && block.scoped_resource_id.nil?
      raise "Unexpected attachments" if block.attachments.exists?
    end

    def self.apply!(block, backup_path)
      raise "An absolute BACKUP_PATH is required" unless backup_path.to_s.start_with?("/")
      block.with_lock do
        guard!(block)
        raise "Expected an HTML block" unless block.manifest_name == "html"
        raise "Another Berlin map already exists" if Decidim::ContentBlock.where(organization: block.organization, scope_name: "homepage", manifest_name: BerlinDistrictMap::MANIFEST).where.not(id: block.id).exists?
        replacement = convert(block.settings.html_content)
        original = block.attributes.slice("id", "decidim_organization_id", "scope_name", "scoped_resource_id", "manifest_name", "settings", "weight", "published_at")
        backup = { "version" => 1, "host" => block.organization.host, "original" => original, "converted_settings_digest" => digest(replacement) }
        File.open(backup_path, File::WRONLY | File::CREAT | File::EXCL, 0o600) do |file|
          file.write(JSON.pretty_generate(backup))
          file.flush
          file.fsync
        end
        # Use a fresh object so the old manifest/settings schema is not memoized.
        Decidim::ContentBlock.find(block.id).update!(manifest_name: BerlinDistrictMap::MANIFEST, settings: replacement)
      end
    end

    def self.restore!(backup_path)
      backup = JSON.parse(File.read(backup_path))
      raise "Unsupported backup" unless backup["version"] == 1 && backup["host"] == BerlinDistrictMap::HOST
      original = backup.fetch("original")
      block = Decidim::ContentBlock.find(original.fetch("id"))
      block.with_lock do
        guard!(block)
        raise "Organization mismatch" unless block.decidim_organization_id == original.fetch("decidim_organization_id")
        raise "Expected converted block" unless block.manifest_name == BerlinDistrictMap::MANIFEST
        raise "Block has since been edited; review before rollback" unless digest(block[:settings]) == backup.fetch("converted_settings_digest")
        raise "Position/publication changed; review before rollback" unless block.weight == original["weight"] && block.published_at&.iso8601(3) == original["published_at"]&.then { |v| Time.parse(v).iso8601(3) }
        Decidim::ContentBlock.find(block.id).update!(manifest_name: original.fetch("manifest_name"), settings: original.fetch("settings"))
      end
    end
  end
end
