# frozen_string_literal: true

# Remove copied stock translations without replacing EMVI's own wording.
# Usage: bundle exec ruby script/cleanup_legacy_locales.rb --write
# Requires the sibling upstream checkout with official v0.27.0..v0.27.2 tags.
require "yaml"
require "json"
require "date"
require "open3"
require "stringio"
require "rubygems/package"
require "optparse"

options = { upstream: File.expand_path("../../decidim", __dir__), write: false }
OptionParser.new do |parser|
  parser.on("--upstream PATH") { |path| options[:upstream] = File.expand_path(path) }
  parser.on("--write") { options[:write] = true }
end.parse!

def flatten(value, path = [], result = {})
  if value.is_a?(Hash)
    value.each { |key, item| flatten(item, path + [key.to_s], result) }
  else
    result[path.join(".")] = value
  end
  result
end

def parse_yaml(raw)
  YAML.safe_load(raw, permitted_classes: [Date, Time, Symbol], aliases: true) || {}
end

stock = Hash.new { |hash, key| hash[key] = [] }
%w[v0.27.0 v0.27.1 v0.27.2].each do |ref|
  names, status = Open3.capture2("git", "-C", options[:upstream], "ls-tree", "-r", "--name-only", ref)
  abort "Cannot read #{ref}" unless status.success?
  paths = names.lines.map(&:strip).select { |path| path.match?(%r{\Adecidim-[^/]+/config/locales/[^/]+\.yml\z}) }
  abort "No official locale files found for #{ref}" if paths.empty?
  archive, error, status = Open3.capture3("git", "-C", options[:upstream], "archive", ref, "--", *paths, binmode: true)
  abort error unless status.success?
  Gem::Package::TarReader.new(StringIO.new(archive)) do |tar|
    tar.each do |entry|
      next unless entry.file?

      flatten(parse_yaml(entry.read)).each do |key, value|
        stock[key] << value unless stock[key].include?(value)
      end
    end
  end
end

removed = Hash.new(0)
changed_files = []
deleted_files = []
Dir.glob(File.expand_path("../config/locales/*.{yml,yaml}", __dir__)).sort.each do |file|
  original = File.read(file)
  data = parse_yaml(original)
  prune = lambda do |mapping, path|
    mapping.each_with_object({}) do |(key, value), result|
      keys = path + [key.to_s]
      if value.is_a?(Hash)
        child = prune.call(value, keys)
        result[key] = child unless child.empty?
      else
        # Regional variants inherit their base locale in Rails, e.g. ar-SA -> ar.
        # Do not compare bs/sr with Croatian or any unrelated language.
        locale, *suffix = keys
        candidates = [locale, locale.split("-").first].uniq.map { |name| ([name] + suffix).join(".") }
        identical_stock_text = value.is_a?(String) && candidates.any? { |name| stock[name].include?(value) }
        # This application correction intentionally differs from upstream.
        protected_file = %w[pl.terms_of_service.yml zz.emvi_030_compatibility.yml].include?(File.basename(file))
        if identical_stock_text && !protected_file
          removed[locale] += 1
        else
          result[key] = value
        end
      end
    end
  end
  result = prune.call(data, [])
  next if result == data

  changed_files << File.basename(file)
  if result.empty?
    deleted_files << File.basename(file)
    File.unlink(file) if options[:write]
  else
    serialized = YAML.dump(result, line_width: -1)
    abort "YAML roundtrip changed #{file}" unless parse_yaml(serialized) == result
    File.write(file, serialized) if options[:write]
  end
end
puts JSON.pretty_generate(write: options[:write], removed_values_by_locale: removed, removed_values: removed.values.sum,
                          changed_files: changed_files.length, deleted_files: deleted_files.length)
