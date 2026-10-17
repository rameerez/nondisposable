# frozen_string_literal: true

# Replays the measured upstream lists through the gem's OWN parser, merge and
# precedence code, so the numbers in 2026-10-17-multi-source-measurement.md can
# be regenerated after any change to them.
#
#   bundle exec ruby docs/evidence/multi_source_measurement.rb LISTS_DIR [TRANCO_CSV]
#
# LISTS_DIR holds one raw download per source, named after the file stems
# below (the URLs are the Source constants in lib/nondisposable/source.rb).
# TRANCO_CSV is the Tranco top-1M "rank,domain" file; optional.
require "bundler/setup"
require "set"
$LOAD_PATH.unshift File.expand_path("../../lib", __dir__)

module Nondisposable
  # The precedence filter reads only these three settings.
  class Configuration
    attr_accessor :excluded_domains, :additional_domains, :block_privacy_relays
  end

  def self.configuration
    @configuration ||= Configuration.new.tap do |c|
      c.excluded_domains = []
      c.additional_domains = []
      c.block_privacy_relays = false
    end
  end
end
%w[domain public_suffix precedence source source_merge].each { |file| require "nondisposable/#{file}" }

lists_dir, tranco_csv = ARGV
abort "usage: #{$PROGRAM_NAME} LISTS_DIR [TRANCO_CSV]" unless lists_dir

S = Nondisposable::Sources
FILES = {
  S::DISPOSABLE_EMAIL_DOMAINS => "ded", S::FAKEFILTER => "fakefilter", S::DISPOSABLE => "disposable",
  S::MAILCHECKER => "mailchecker", S::GROUNDCAT => "groundcat", S::WESBOS => "wesbos"
}.freeze

parsed = FILES.to_h { |source, stem| [source, Nondisposable::Source.parse(File.read(File.join(lists_dir, "#{stem}.txt")))] }
tranco = tranco_csv ? File.foreach(tranco_csv).first(100_000).map { |line| line.split(",")[1].to_s.strip }.to_set : Set.new

build = lambda do |sources|
  snapshots = sources.to_h { |source| [source, parsed.fetch(source)] }.transform_values(&:domains)
  Nondisposable::Precedence.filter(Nondisposable::SourceMerge.call(snapshots, threshold: 2).domains)
end
variant = lambda do |source, **overrides|
  source.with(**overrides).tap { |copy| parsed[copy] = parsed.fetch(source) }
end
report = lambda do |label, result, baseline|
  added = result.kept - baseline.kept
  line = "#{label}: #{result.kept.size} (+#{added.size} -#{(baseline.kept - result.kept).size})"
  line += ", mail-burn.com=#{result.kept.include?('mail-burn.com')}"
  line += ", Tranco top-100k additions: #{(added & tranco).size}" unless tranco.empty?
  puts line
  added
end

puts "== Sources"
parsed.each do |source, list|
  puts "#{source.name}: #{list.domains.size} unique domains, #{list.lines} lines, #{list.invalid} unparseable"
end

default = build.call(S::DEFAULT)
recommended = build.call(S::RECOMMENDED)
puts "\n== Presets (after the precedence filter)"
puts "DEFAULT: #{default.kept.size}, dropped #{default.dropped_by_reason}"
added = report.call("RECOMMENDED", recommended, default)
puts "  dropped: #{recommended.dropped_by_reason}"
puts "  Tranco top-100k additions: #{(added & tranco).to_a.sort.join(' ')}" unless tranco.empty?

puts "\n== Corroboration"
report.call("RECOMMENDED + disposable, mailchecker, groundcat (lineage)",
            build.call(S::RECOMMENDED + [S::DISPOSABLE, S::MAILCHECKER, S::GROUNDCAT]), recommended)
naive = [S::DISPOSABLE, S::MAILCHECKER, S::GROUNDCAT].map { |source| variant.call(source, derived_from: []) }
naive_added = report.call("same, lineage IGNORED", build.call(S::RECOMMENDED + naive), recommended)
puts "  e.g. #{(naive_added & tranco).to_a.sort.first(30).join(' ')}" unless tranco.empty?
report.call("RECOMMENDED + all four incl. wesbos (lineage)",
            build.call(S::RECOMMENDED + [S::DISPOSABLE, S::MAILCHECKER, S::GROUNDCAT, S::WESBOS]), recommended)

puts "\n== disposable/disposable as a PRIMARY"
aggressive = build.call(S::RECOMMENDED + [variant.call(S::DISPOSABLE, trust: :primary)])
aggressive_added = report.call("RECOMMENDED + DISPOSABLE primary", aggressive, recommended)
puts "  dropped as never-disposable: #{aggressive.dropped_by_reason[:never_disposable]&.size}"
puts "  e.g. #{(aggressive_added & tranco).to_a.sort.first(40).join(' ')}" unless tranco.empty?
