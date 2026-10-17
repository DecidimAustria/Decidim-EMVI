# frozen_string_literal: true

namespace :emvi do
  namespace :berlin_map do
    desc "Preview conversion of the Berlin HTML map; APPLY=1 BACKUP_PATH=/absolute/file.json writes changes"
    task convert: :environment do
      organization = Decidim::Organization.find_by!(host: Emvi::BerlinDistrictMap::HOST)
      block = Decidim::ContentBlock.where(organization: organization).find(Integer(ENV.fetch("BLOCK_ID")))
      Emvi::BerlinMapConversion.guard!(block)
      abort "Already converted; no changes made" if block.manifest_name == Emvi::BerlinDistrictMap::MANIFEST
      abort "Expected HTML block" unless block.manifest_name == "html"
      settings = Emvi::BerlinMapConversion.convert(block.settings.html_content)
      puts JSON.pretty_generate(block_id: block.id, host: organization.host, locales: settings.fetch("title").keys, weight: block.weight, published: block.published?, mode: ENV["APPLY"] == "1" ? "apply" : "preview")
      if ENV["APPLY"] == "1"
        Emvi::BerlinMapConversion.apply!(block, ENV.fetch("BACKUP_PATH"))
        puts "Converted. Copy the backup out of the pod before it is replaced."
      end
    end

    desc "Preview or restore the original Berlin HTML block from BACKUP_PATH; APPLY=1 writes changes"
    task restore: :environment do
      path = ENV.fetch("BACKUP_PATH")
      backup = JSON.parse(File.read(path))
      puts JSON.pretty_generate(block_id: backup.fetch("original").fetch("id"), host: backup.fetch("host"), mode: ENV["APPLY"] == "1" ? "restore" : "preview")
      Emvi::BerlinMapConversion.restore!(path) if ENV["APPLY"] == "1"
    end
  end
end
