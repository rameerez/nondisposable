# frozen_string_literal: true

# Turns the raw evidence into the labelled corpus the test suite reads.
#
#   ruby script/label_lookalike_corpus.rb \
#     docs/evidence/2026-10-17-lookalike-evidence.csv \
#     test/fixtures/lookalike_corpus.csv
#
# Three labels, and the asymmetry between them is the point:
#
#   typo       a misspelling of a provider that nobody has a mailbox at, with
#              direct evidence (see the header of data/known_typo_domains.txt).
#              Only rows labelled here can ever be refused outright.
#   real       an organisation or service: a working site of its own, or mail
#              hosted somewhere people actually read it.
#   uncertain  everything else. Not a polite "probably typo": the evidence does
#              not say, so the gem must not act as if it did.
#
# The rules below are deliberately crude and only ever produce `real` or
# `uncertain`, except for impossible TLDs. Every `typo` label is a REVIEWED
# entry in TYPO (and a few rows the rules would get wrong are pinned in
# PINNED), each with the evidence a person read — website appearance is
# evidence, not proof (plan §6.A, codex finding 2), so no rule is trusted to
# make that call alone.
require 'csv'
require 'digest'
require 'set'

INPUT, OUTPUT = ARGV
abort "usage: #{$PROGRAM_NAME} evidence.csv corpus.csv" unless INPUT && OUTPUT

TLDS = File.readlines(File.expand_path('../data/iana_tlds.txt', __dir__), chomp: true)
           .reject { |l| l.start_with?('#') }.map(&:downcase).to_set

# Reviewed 2026-10-17 against the evidence CSV plus manual dig/curl follow-ups
# where the automated pass timed out.
TYPO = {
  'gmial.com' => 'no MX; homepage redirects to flyls.com, an unrelated product buying typo traffic',
  'gmai.com' => 'MX mail.h-email.net (Bodis parking); ww1. parking lander',
  'gmeil.com' => 'MX mail.h-email.net (Bodis parking); ww1. parking lander',
  'gmaio.com' => 'MX mail.h-email.net (Bodis parking); "Loading..." parking lander',
  'gamail.com' => 'Sedo parking lander, "o domínio pode estar à venda"; MX localhost',
  'gimail.com' => 'Sedo parking lander, "o domínio pode estar à venda"; MX localhost',
  'gmaii.com' => 'Sedo parking lander; MX localhost',
  'gmuil.com' => 'above.com parking (MX park-mx.above.com), "this domain may be for sale"',
  'gm4il.com' => 'Afternic (for sale) nameservers; Null MX (RFC 7505, accepts no mail)',
  'hmail.com' => 'Afternic (for sale) nameservers; Null MX (RFC 7505, accepts no mail)',
  'gmmail.com' => 'renewyourname.net (expired-domain parking) nameservers; no MX',
  'gmali.com' => 'no MX; homepage redirects to primequote.com, unrelated insurance ads',
  'gmil.com' => 'webmasters.com typo portfolio; MX mail.yaxmail.net, the catch-all shared with hotmil.com',
  'hotmil.com' => 'webmasters.com typo portfolio; MX mail.yaxmail.net, the catch-all shared with gmil.com',
  'gmail.co' => 'Google-served 404 page; no MX (Google defensive registration)',
  'gmail.cm' => 'redirects to accounts.google.com; no MX (Google defensive registration)',
  'gmal.com' => 'registered (Google Domains NS) with neither MX nor A: mail to it is undeliverable; observed CarHey typo',
  'jmail.com' => '"JMail.com for sale" marketplace lander; no MX; observed CarHey typo',
  'yhoo.it' => 'redirects to yahoo.com; no MX (Yahoo defensive registration)',
  'yaho.com' => 'redirects to yahoo.com; no MX (Yahoo defensive registration)',
  'yhoo.com' => 'redirects to yahoo.com; no MX (Yahoo defensive registration)',
  'yhaoo.com' => 'redirects to yahoo.com; no MX (Yahoo defensive registration)',
  'yaoo.com' => 'redirects to yahoo.com; no MX (Yahoo defensive registration)',
  'yahho.com' => 'redirects to yahoo.com; no MX (Yahoo defensive registration)',
  'yaho.de' => 'Yahoo-branded 404 page; no MX (Yahoo defensive registration)',
  'homail.com' => 'redirects to outlook.live.com; no MX (Microsoft defensive registration)',
  'hotamil.com' => 'redirects to outlook.live.com; no MX (Microsoft defensive registration)',
  'otmail.com' => 'redirects to outlook.live.com; no MX (Microsoft defensive registration)',
  'hotmal.com' => 'redirects to outlook.live.com; no MX (Microsoft defensive registration)',
  'hotmai.com' => 'Azure DNS (Microsoft); its only MX is itself, which has no A record: undeliverable',
  'hitmail.com' => 'ww80. parking lander; no MX',
  'hotmial.com' => 'ParkingCrew nameservers; no MX',
  'outlok.com' => 'ParkingCrew nameservers; no MX',
  'hotmasil.com' => 'no MX; homepage redirects to aboutfinance.org, unrelated ads',
  'autlook.com' => '"Redirecting..." lander; MX mx156.hostedmxserver.com, the catch-all ol.com shares with pltraffic7.com (parking traffic)',
  'outloo.com' => '"Redirecting..." lander; MX mx156.hostedmxserver.com, the catch-all ol.com shares with pltraffic7.com (parking traffic)',
  'icloude.com' => 'redirects to apple.com; no MX (Apple defensive registration)',
  'icioud.com' => 'no MX; homepage redirects to gaja79.com, unrelated',
  'zoho.co' => 'redirects to zoho.com; no MX (Zoho defensive registration)',
  'yndex.ru' => 'no MX; homepage redirects to 21i.ru, unrelated',
  'ayndex.ru' => 'same server (37.46.135.110) and own MX as yandez.ru: a portfolio of Yandex misspellings',
  'yandez.ru' => 'same server (37.46.135.110) and own MX as ayndex.ru: a portfolio of Yandex misspellings',
  'globoi.com' => 'nameservers ns01.globo.com and MX corp.globo.com: held by Globo itself (defensive registration)',
  'sbcglobal.et' => '"Future home of sbcglobal.et" placeholder for a misspelling of sbcglobal.net',
  'rfunbox.com' => 'registered (Route 53 NS) with neither MX nor A: mail to it is undeliverable',
  'ffrontier.com' => 'registered (Akamai NS) with neither MX nor A: mail to it is undeliverable',
  'globh.com' => 'registered (Route 53 NS) with neither MX nor A: mail to it is undeliverable'
}.freeze

# Rows the crude rules would label wrongly in either direction. Each one says
# why it is not what the rules would make it.
PINNED = {
  'pate.com' => ['uncertain', 'parked "may be for sale", but a dictionary word (pâté), not a misspelling of nate.com'],
  'sna.com' => ['uncertain', 'parking search page, but a three-letter premium name, not a misspelling of sina.com'],
  'cmail.com' => ['uncertain', '"Domain for sale" and no MX, but c is nowhere near g: a generic name, not shown to be a typo'],
  'gmall.com' => ['uncertain', 'a GitHub Pages site titled GMALL.COM; could be a "G mall" brand'],
  'zahoo.com' => ['uncertain', 'redirects to yahoo.com but publishes its own MX (a.mx.zahoo.com): somebody may read that mail'],
  'duck.co' => ['uncertain', 'redirects to duckduckgo.com but has Microsoft 365 MX: DuckDuckGo staff may use it'],
  'hotnail.com' => ['uncertain', 'ParkingCrew-range IP and an MX of its own; page did not load'],
  'gmail.ru' => ['uncertain', 'no MX, no site; the suggestion (mail.ru) is not even what the user would mean'],
  'yandeg.ru' => ['uncertain', 'MX mx.yandex.ru (Yandex-hosted mail): could be a defensive registration or a Yandex 360 customer'],
  'mail.ch' => ['real', 'mail.de\'s Swiss provider: a real mailbox service'],
  'mail.be' => ['real', 'Belgian mailbox provider ("an easy to remember emailaddress")'],
  'inbox.eu' => ['real', 'inbox.eu mailbox provider'],
  'mailo.com' => ['real', 'Mailo mailbox provider'],
  'memail.com' => ['real', 'MeMail mailbox provider'],
  'xmail.ru' => ['real', 'Mail.ru\'s xmail.ru mailbox service'],
  '5ymail.com' => ['real', 'anonymous email service'],
  'pmail.com' => ['real', 'Pegasus Mail / Mercury (mail software since 1990), own MX'],
  'gamil.com' => ['real', '"Gamil finds positive stories" with its own MX: an organisation'],
  'gmsil.com' => ['real', 'Group Marketing Services, own MX'],
  'airtel.ne' => ['real', 'Airtel Niger, a mobile operator'],
  'yandex.eu' => ['uncertain', 'redirects to yandex.com with no MX: Yandex-held, but nobody has shown it is typed by mistake'],
  'iclod.com' => ['uncertain', 'MX at orcon.net.nz (a New Zealand ISP): somebody\'s real mail, or a stale record']
}.freeze

PARKING_NS = /parkingcrew|sedoparking|bodis|above\.com|afternic|dan\.com|renewyourname|hugedomains|uniregistry/i.freeze
CHALLENGE = /just a moment|access denied|attention required|forbidden|not found|error|bad gateway|unavailable|security checkpoint|redirecting|killbot|checking browser|loading|test page|\A\s*\d{3}\s*\z|\A\s*\z/i.freeze
# Titles a parking or placeholder page serves, which the body markers miss.
PARKED_TITLE = /parked|may be available|coming soon|future home/i.freeze
# Catch-alls that collect mail for misspelled domains; MX there is not a sign
# that people use the domain.
CATCHER_MX = /h-email\.net|yaxmail|hostedmxserver|park-mx|^localhost$/i.freeze

def label_for(row)
  domain = row['domain']
  return ['typo', TYPO.fetch(domain)] if TYPO.key?(domain)
  return PINNED.fetch(domain) if PINNED.key?(domain)

  tld = domain.include?('.') ? domain.split('.').last : nil
  return ['typo', "impossible TLD#{tld ? " .#{tld}" : ' (no dot at all)'}: no mail can be delivered"] unless tld && TLDS.include?(tld)

  mx = row['mx'].to_s.split
  title = row['title'].to_s.gsub(/&[a-z#0-9]+;/i, ' ').strip
  parked = !row['parking_markers'].to_s.empty? || row['ns'].to_s.match?(PARKING_NS) || title.match?(PARKED_TITLE)

  if parked
    signals = [row['parking_markers'], row['ns'].to_s.match?(PARKING_NS) ? row['ns'] : nil, title.match?(PARKED_TITLE) ? title : nil]
    ['uncertain', "parked or for sale (#{signals.reject { |v| v.to_s.empty? }.join('; ')}), not reviewed as a typo"]
  elsif !title.match?(CHALLENGE) && title.length > 2
    ['real', "site: #{title[0, 80]}"]
  elsif mx.any? && mx != ['.'] && mx.none? { |h| h.match?(CATCHER_MX) }
    ['real', "receives mail at #{mx.first}"]
  else
    ['uncertain', [mx.empty? ? 'no MX' : "MX #{mx.join(' ')}", row['http_code'].to_s.empty? || row['http_code'] == '000' ? 'no site' : "HTTP #{row['http_code']}"].join(', ')]
  end
end

rows = CSV.read(INPUT, headers: true)
missing = (TYPO.keys + PINNED.keys) - rows.map { |r| r['domain'] }
abort "reviewed domains missing from the evidence: #{missing.join(', ')}" if missing.any?

CSV.open(OUTPUT, 'w') do |csv|
  csv << %w[domain suggestion label evidence]
  rows.sort_by { |r| r['domain'] }.each do |row|
    label, evidence = label_for(row)
    csv << [row['domain'], row['suggestion'], label, evidence]
  end
end

counts = CSV.read(OUTPUT, headers: true).map { |r| r['label'] }.tally
warn "wrote #{OUTPUT}: #{counts.sort.map { |k, v| "#{k}=#{v}" }.join(' ')}"
