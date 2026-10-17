# frozen_string_literal: true

# Collects the raw evidence used to label test/fixtures/lookalike_corpus.csv.
#
#   ruby script/collect_lookalike_evidence.rb \
#     docs/evidence/2026-10-17-tranco-top1m-lookalike-hits.csv \
#     docs/evidence/2026-10-17-lookalike-evidence.csv
#
# For every domain the current lookalike rule flags it records what a visitor
# and a mail server would see: the final URL and <title> of the homepage after
# redirects (curl, 8 s), the MX hosts and nameservers (dig), and a handful of
# parking/for-sale markers in the page body. Nameservers matter more than they
# look: a domain delegated to a parking network (parkingcrew, afternic, sedo)
# or to the provider's own DNS says who holds it, which a homepage that only
# renders in JavaScript does not. An MX of "." is a Null MX (RFC 7505): the
# domain declares that it accepts no mail at all. It does NOT decide anything — labels are a separate,
# reviewed step, because "the homepage is parked" is evidence, not proof that
# nobody receives mail there (plan §6.A, codex finding 2).
#
# Polite by construction: at most 8 domains in flight, one GET per domain, a
# plain browser-ish User-Agent naming this script, no retries. Needs only curl
# and dig on PATH; no gems.
require 'csv'
require 'set'
require 'open3'
require 'timeout'

INPUT, OUTPUT = ARGV
abort "usage: #{$PROGRAM_NAME} hits.csv evidence.csv" unless INPUT && OUTPUT

CONCURRENCY = 8
TIMEOUT_SECONDS = 8
USER_AGENT = 'Mozilla/5.0 (compatible; nondisposable-evidence/1.0; +https://github.com/rameerez/nondisposable)'

# Typos seen on real CarHey accounts (2026-10) and in this gem's own tests,
# added to the Tranco hits so the corpus covers what users actually type, not
# only what happens to be popular enough to be in the top 1M.
EXTRA = {
  'gmailmcom' => 'gmail.com', 'gmail.con' => 'gmail.com', 'outlook.ed' => 'outlook.es',
  'gmai.com' => 'gmail.com', 'gmal.com' => 'gmail.com', 'jmail.com' => 'gmail.com',
  'gmial.com' => 'gmail.com', 'hotmial.com' => 'hotmail.com', 'gmail.co' => 'gmail.com',
  'gmail.cm' => 'gmail.com', 'gmail.om' => 'gmail.com', 'yaho.com' => 'yahoo.com',
  'outlok.com' => 'outlook.com', 'iclod.com' => 'icloud.com'
}.freeze

# Phrases that registrars, parking networks and domain marketplaces put on the
# pages they serve for domains nobody is using. Matched case-insensitively
# against the first 200 KB of the body.
PARKING_MARKERS = [
  'domain is for sale', 'this domain may be for sale', 'buy this domain', 'make an offer',
  'domain for sale', 'is for sale', 'parked free', 'parkingcrew', 'sedoparking', 'sedo.com',
  'bodis', 'afternic', 'dan.com', 'hugedomains', 'undeveloped.com', 'above.com',
  'domain has expired', 'this domain is parked', 'related searches', 'godaddy.com/domainsearch'
].freeze

def run(*cmd)
  out, _status = Timeout.timeout(TIMEOUT_SECONDS + 4) { Open3.capture2e(*cmd) }
  out
rescue Timeout::Error, StandardError
  ''
end

# [status, records]. The status is dig's own (NOERROR, NXDOMAIN, SERVFAIL) or
# TIMEOUT, so an empty answer from a server that replied can never be confused
# with a lookup that failed: only "NOERROR and empty" proves a record is absent.
def dig(type, domain)
  out = run('dig', '+noall', '+comments', '+answer', '+time=4', '+tries=2', type, domain)
  status = out[/status: ([A-Z]+)/, 1] || 'TIMEOUT'
  records = out.lines.map(&:strip).reject { |l| l.empty? || l.start_with?(';') }
               .select { |l| l.split[3].to_s.casecmp?(type) }.map { |l| l.split[4..].join(' ') }
  [status, records]
end

def mx_for(domain)
  status, records = dig('MX', domain)
  [status, records.map { |l| l.split.last.to_s.delete_suffix('.') }.map { |h| h.empty? ? '.' : h }.sort.uniq]
end

def ns_for(domain)
  dig('NS', domain).last.map { |l| l.delete_suffix('.') }.sort.uniq
end

# "MX:NOERROR A:NOERROR AAAA:NOERROR" plus which address records exist.
def addresses_for(domain)
  %w[A AAAA].map { |type| [type, *dig(type, domain)] }
end

def http_for(domain)
  marker = '__NONDISPOSABLE_META__'
  body = run('curl', '-sS', '-L', '--max-redirs', '6', '--max-time', TIMEOUT_SECONDS.to_s,
             '--max-filesize', '2000000', '-A', USER_AGENT, '-o', '-',
             '-w', "\n#{marker}%{http_code} %{url_effective}", "http://#{domain}/")
  meta = body.rpartition(marker).last.to_s.strip
  code, final = meta.split(' ', 2)
  page = body.rpartition(marker).first.to_s[0, 200_000].to_s.scrub('')
  title = page[%r{<title[^>]*>(.*?)</title>}im, 1].to_s.gsub(/\s+/, ' ').strip[0, 120]
  parked = PARKING_MARKERS.select { |m| page.downcase.include?(m) }
  { code: code.to_s, final: final.to_s, title: title, parked: parked }
end

rows = CSV.read(INPUT).map { |rank, domain, suggestion| [rank, domain, suggestion] }
seen = rows.map { |r| r[1] }.to_set
EXTRA.each { |domain, suggestion| rows << ['extra', domain, suggestion] unless seen.include?(domain) }

queue = Queue.new
rows.each { |r| queue << r }
results = Queue.new

workers = Array.new(CONCURRENCY) do
  Thread.new do
    loop do
      rank, domain, suggestion = queue.pop(true)
      # A domain with no valid TLD has nothing to fetch: it cannot be registered.
      if domain.count('.').zero? || %w[con ed].include?(domain.split('.').last)
        results << [rank, domain, suggestion, '', '', '', '', '', '', '', '']
        next
      end

      http = http_for(domain)
      mx_status, mx = mx_for(domain)
      addresses = addresses_for(domain)
      dns = ["MX:#{mx_status}", *addresses.map { |type, status, _| "#{type}:#{status}" }].join(' ')
      resolves = addresses.any? { |_, _, records| records.any? } ? 'yes' : 'no'
      results << [rank, domain, suggestion, dns, resolves, mx.join(' '), ns_for(domain).join(' '),
                  http[:code], http[:final], http[:title], http[:parked].join('|')]
    rescue ThreadError
      break
    end
  end
end

progress = Thread.new { loop { sleep 15; warn "#{results.size}/#{rows.size}" } }
workers.each(&:join)
progress.kill

CSV.open(OUTPUT, 'w') do |csv|
  csv << %w[rank domain suggestion dns_status resolves mx ns http_code final_url title parking_markers]
  out = []
  out << results.pop until results.empty?
  out.sort_by { |r| [r[0] == 'extra' ? 1 : 0, r[0].to_i, r[1]] }.each { |r| csv << r }
end
warn "wrote #{rows.size} rows to #{OUTPUT}"
