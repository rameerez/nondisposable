# frozen_string_literal: true

# Reproduces docs/evidence/2026-10-17-tranco-top1m-lookalike-hits.csv: every
# domain in a Tranco list that the 0.4.0 lookalike rule would have flagged.
#
#   ruby docs/evidence/tranco_lookalike_scan.rb top-1m.csv hits.csv
#
# The input is the Tranco top-1M CSV ("rank,domain"), downloaded 2026-10-17
# from https://tranco-list.eu/top-1m.csv.zip (file dated 2026-10-16, sha256
# prefix a166c559bdf76fce).
#
# PINNED TO THE BASELINE. This script does not load the gem: the ranker has
# changed since (that is the point of the scan), and loading it would measure
# the new rule instead of the one under test. Instead it carries the 0.4.0
# algorithm verbatim — exact-provider exemption, then optimal string alignment
# distance <= 1 against the provider list, first candidate in list order —
# and reads the provider list as it was at the 0.4.0 merge (6032146) from git.
require 'open3'
require 'set'

BASELINE = '6032146'
INPUT, OUTPUT = ARGV
abort "usage: #{$PROGRAM_NAME} top-1m.csv hits.csv" unless INPUT && OUTPUT

repo = File.expand_path('../..', __dir__)
list, status = Open3.capture2('git', '-C', repo, 'show', "#{BASELINE}:data/email_providers.txt")
abort "cannot read data/email_providers.txt at #{BASELINE} (is this a git checkout with that commit?)" unless status.success?

PROVIDERS = list.lines.map { |l| l.strip.downcase }.reject { |l| l.empty? || l.start_with?('#') }.freeze
PROVIDER_SET = PROVIDERS.to_set.freeze

# 0.4.0's Suggestion#osa_distance, unchanged.
def osa_distance(a, b, cutoff)
  prev_prev = nil
  prev = (0..b.length).to_a
  current = Array.new(b.length + 1)
  a.each_char.with_index do |a_char, i|
    current[0] = i + 1
    row_min = current[0]
    b.each_char.with_index do |b_char, j|
      cost = a_char == b_char ? 0 : 1
      value = [current[j] + 1, prev[j + 1] + 1, prev[j] + cost].min
      value = [value, prev_prev[j - 1] + cost].min if i.positive? && j.positive? && a_char == b[j - 1] && a[i - 1] == b_char
      current[j + 1] = value
      row_min = value if value < row_min
    end
    return cutoff if row_min >= cutoff

    prev_prev = prev
    prev = current.dup
  end
  prev[b.length]
end

# 0.4.0's Suggestion.correct_domain at the default lookalike_distance of 1.
def baseline_correction(domain)
  domain = domain.to_s.strip.downcase.delete_suffix('.')
  return nil if domain.empty? || PROVIDER_SET.include?(domain)

  best = nil
  best_distance = 2
  PROVIDERS.each do |candidate|
    next if (candidate.length - domain.length).abs > 1

    distance = osa_distance(domain, candidate, best_distance)
    next if distance >= best_distance

    best = candidate
    best_distance = distance
    break if distance == 1
  end
  best
end

n = 0
File.open(OUTPUT, 'w') do |out|
  File.foreach(INPUT) do |line|
    rank, domain = line.strip.split(',', 2)
    suggestion = baseline_correction(domain)
    next unless suggestion

    out.puts "#{rank},#{domain},#{suggestion}"
    n += 1
  end
end
puts "flagged=#{n}"
