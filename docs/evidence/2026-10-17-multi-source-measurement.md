# Multi-source blocklists: measurement, 2026-10-17

Inputs: one raw download of each source on 2026-10-17 (URLs: the `Source`
constants in `lib/nondisposable/source.rb`), the Tranco top-1M list of the same
day (see the lookalike plan for its hash), and the gem's own code at the commit
that adds this file. Regenerate every number below with:

    bundle exec ruby docs/evidence/multi_source_measurement.rb LISTS_DIR TRANCO_CSV

Tranco membership is not proof of a false positive (popular temp-mail sites are
in it too). It is a cheap flag for domains worth a human look.

## Sources

| Source | Unique domains | Public suffixes it lists | Known real providers it lists |
|---|---|---|---|
| disposable-email-domains (default) | 9,895 | 0 | `sify.com`, `21cn.com` |
| fakefilter | 4,841 (10,652 lines) | `it.com`, `zone.id`, `f5.si` | 0 |
| disposable/disposable | 97,562 | 32 (`ddns.net`, `cloudns.org`…) | `broadpark.no`, `sify.com`, `ybb.ne.jp`, `wo.com.cn`, `odn.ad.jp`, `uqmobile.jp`, `sanook.com`, `51.com`, regional `*.rr.com` |
| mailchecker | 56,512 | 20 (`nom.za`, `zp.ua`…) | 15 privacy relays, `tom.com`, `mtu-net.ru`, `sdf.org` |
| groundcat | 21,453 | 14 (`dyndns.org`, `it.com`…) | `broadpark.no`, `ybb.ne.jp` |
| wesbos | 27,277 | 14 (`my.id`, `net.ua`…) | `freemail.hu`, `sify.com`, `sohu.com`, `tom.com` |

"Known real" = `data/email_providers.txt`, `data/never_disposable.txt` (whose
measured section was built from this table) and the privacy relays.

## Presets, after the precedence filter

- `DEFAULT`: 9,893 stored. Two domains the upstream list carries are no longer
  blocked: `sify.com` (Indian ISP) and `21cn.com` (China Telecom webmail).
- `RECOMMENDED` (default + fakefilter, both primary): 13,168, **+3,275**.
  Dropped: the two above, and three public suffixes. Additions in the Tranco
  top 100k: `fr.nf`, `kro.kr`, `torrentclub.online`,
  `aboutbeautifulgallopinghorsesinthegreenpasture.online` (free-redirect and
  temp-mail domains).
- `mail-burn.com` (the 2026-10-16 incident domain) is in **neither**. It is in
  disposable/disposable (own crawl) and groundcat (which imports
  disposable/disposable): one origin.

## Corroboration

- `RECOMMENDED` + disposable, mailchecker, groundcat as corroborating, lineage
  declared: **+0**. Every agreement among them is explained by an upstream.
- Same, lineage ignored: +68,692 (catches `mail-burn.com`), 64 in the Tranco top
  100k: `compaq.com`, `cafe24.com`, `24hourfitness.com`, `asana.biz`,
  `backblazeb2.com`…
- Adding wesbos (no declared lineage, 57% overlap with mailchecker): +11,744,
  21 in the top 100k, including real providers `tom.com` and `sdf.org` (now in
  `never_disposable.txt`).

## disposable/disposable as a primary

+84,341 over `RECOMMENDED`, 70 in the Tranco top 100k, 36 dropped as
never-disposable. Unprotected examples: `cafe24.com`, `24hourfitness.com`,
`foxwoods.com`, `asana.biz`, `namecheap.com`. Not recommended; documented as an
informed opt-in.
