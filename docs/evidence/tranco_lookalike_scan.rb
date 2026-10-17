$LOAD_PATH.unshift File.expand_path("~/GitHub/nondisposable/lib")
require "set"
module Nondisposable; end
require "nondisposable/suggestion"
Conf = Struct.new(:lookalike_distance, :additional_email_providers)
module Nondisposable; def self.configuration = (@c ||= Conf.new(1, [])); end
out = File.open(ARGV[1], "w")
n = 0
File.foreach(ARGV[0]) do |line|
  rank, d = line.strip.split(",", 2)
  s = Nondisposable::Suggestion.correct_domain(d)
  if s then out.puts "#{rank},#{d},#{s}"; n += 1 end
end
puts "flagged=#{n}"
