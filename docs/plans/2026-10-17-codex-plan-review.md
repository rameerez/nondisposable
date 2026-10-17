1. **[blocker] The oracle is circular.** A2 allowlists every A1 `real` row, guaranteeing those tests pass regardless of algorithm quality. Returning no suggestions also passes because recall has no floor. **Change:** evaluate rules separately from exemptions, using an untouched holdout and minimum recall on independently confirmed typos.

2. **[major] Labels confuse website appearance with email intent.** Parked, for-sale, and redirecting domains can still carry legitimate mail. Missing MX is insufficient: SMTP supports implicit MX fallback. Human review concentrates on `real` verdicts, leaving dangerous false `typo` labels unchecked. **Change:** review proposed rejection labels; preserve uncertainty. [SMTP specification](https://www.rfc-editor.org/rfc/rfc5321.html#section-5.1)

3. **[major] The keyboard model still rejects unseen employers.** `teia.com` uses [published email addresses](https://help.teiacrm.com.br/), is absent from the supplied corpus/provider list, and matches the permitted deletion rule against `telia.com`. QWERTZ adjacency would additionally admit `zozo.com → zoho.com`. **Change:** use keyboard likelihood for hints, not proof warranting rejection.

4. **[major] “TLD-side edits stay permissive” preserves a false-positive class.** The evidence contains `web.dev → web.de`, `yahoo.com.au → yahoo.com.ar`, and `yahoo.com.my → yahoo.com.mx`. Exempting observed examples cannot protect unseen country variants. **Change:** distinguish invalid endings from valid alternative suffixes; keep the latter advisory.

5. **[blocker] Public-suffix poisoning can block entire namespaces.** A primary adding `co.uk`, `com.br`, `com.es`, or `com.mx` reaches existing parent matching and rejects ordinary domains beneath it. Only C explicitly prohibits PSL entries. **Change:** apply PSL validation to every ingestion path; specify registrable-label handling and preserve legitimate subdomains such as `alumnos.upm.es`.

6. **[major] Canonicalization is unspecified and currently inconsistent.** Suggestions strip trailing dots; database checks do not consistently do so. Unicode `bücher.de` and `xn--bcher-kva.de` need equivalent decisions, while punycode character distance has no keyboard meaning. **Change:** share domain normalization across configuration, ingestion, and checks; preserve local-part case and `+tags`; test uppercase/trailing dots and IDN equivalence.

7. **[minor] The stated experiment disagrees with its artifact.** The CSV contains **707 unique domains**, all replaying successfully against current code—not 698. Target counts also differ. Tranco list ID, input hash, and measurement scripts are absent. **Change:** commit reproducible inputs and regenerate the plan’s measurements.

8. **[major] Two repositories are not two independent observations.** `disposable/disposable` explicitly imports mailchecker, fakefilter, and wesbos. One mistaken entry can propagate and acquire multiple “votes”; C feeding back into upstream lists creates another loop. **Change:** count independent evidence origins, deduplicate descriptors, and record copying relationships. [Declared sources](https://github.com/disposable/disposable/blob/master/README.md)

9. **[major] Primary trust permits targeted poisoning.** `gmail.com` should be protected by the proposed allowlist, but an unlisted employer needs only one poisoned primary entry to lose signups. Stable source size provides no protection. **Change:** require poison-input regressions, review suspicious additions, retain previous generations, and provide immediate rollback.

10. **[major] Allowlist and privacy-policy precedence contradict the implementation and each other.** Currently `additional_domains` wins before exclusions. Meanwhile `duck.com` belongs to the proposed unconditional protected set, making `block_privacy_relays = true` ineffective if that protection always wins. **Change:** define one precedence table, separate relay policy from permanent exemptions, and enforce it during validation and seeding.

11. **[major] Count guards are easily bypassed.** One-for-one poisoned replacements, repeated 49% shrinkage, and repeated growth below 3× all pass. Current normalization accepts comments/HTML and checks emptiness before normalization. **Change:** validate unique canonical domains before measuring; inspect additions/removals, enforce streaming byte limits and total deadlines, and validate the final merged set.

12. **[major] A `source` column cannot support the merge semantics.** One domain can have several contributing sources; rejected single-source candidates must also survive for future corroboration. Merged rows cannot reconstruct each source’s last-good contents. **Change:** retain source snapshots and membership sets with fetch status, timestamps, hashes, and explicit retirement rules.

13. **[major] Partial failure and concurrency lack a publication contract.** On first run, failed primaries plus insufficient corroboration can produce an empty merge despite nonempty downloads. Concurrent refreshes or `seed` racing after `none?` can publish stale data. Existing transactions already protect ordinary readers from intermediate deletion. **Change:** preserve atomic replacement, serialize publication/seeding, and specify bootstrap and degraded-run behavior.

14. **[major] Existing-host migration is underspecified.** The current generator creates the table; it cannot upgrade installed hosts. Missing-column writes can fail refreshes, while validation errors default to allowing signups. **Change:** provide an additive upgrade migration, rolling-deployment compatibility, legacy provenance handling, rollback instructions, and adapter-specific concurrency verification.

15. **[blocker] C verifies a claim, not disposable-mail capability.** A malicious generator can display an unrelated employer’s address; MX, low popularity, and screenshots all pass without demonstrating mailbox access. List diffs merely repeat allegations. **Change:** quarantine discoveries; require independently reviewed evidence of actual disposable inbox capability before publication or primary-source promotion.

16. **[major] C lacks evidence integrity, expiry, and an operating budget.** Mutable screenshot paths are weak audit records; domains can change owners while remaining blocked indefinitely. List diffs can generate thousands of browser captures. **Change:** bind evidence to hashed artifacts/run IDs, revalidate entries, support rapid withdrawal, and cap candidates, runtime, storage, and retries with monitored alerts.

17. **[major] C’s ToS/licensing policy is insufficient.** Robots permission is not access authorization. Public screenshots may contain copyrighted material or inbox contents; upstream datasets cannot automatically become CC0 merely by redistribution. **Change:** assess source terms and redistribution rights, retain attribution, redact private content, and restrict probes to controlled mailboxes. [Robots specification](https://www.rfc-editor.org/rfc/rfc9309.html#section-1)

18. **[major] The sequencing overcomplicates the incident response.** Lookalike blocking does not stop SMS pumping with correctly spelled Gmail addresses. **Change:** immediately configure the already-supported `additional_domains` for verified burners, contribute evidence upstream, keep typo hints optional, and address SMS rate/spend limits in the host. Defer C until its maintenance benefit is demonstrated.

**Top 3 changes to make to the plan**

1. Replace memorized “zero false positives” with independent evaluation; keep valid-domain lookalikes advisory.
2. Specify canonicalization, PSL safeguards, precedence, source snapshots, and serialized atomic publication before multi-source rollout.
3. Quarantine C discoveries and simplify the immediate response to verified domain additions plus SMS abuse controls.