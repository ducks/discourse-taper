# Discoverability audit

Date: 2026-11-05. Target: https://archive.depoitrine.com.
Branch: `feature/discoverability-audit`.

Goal: make public archive pages discoverable and understandable to search engines. Sharing previews are secondary. The initial audit is recorded below; implementation was subsequently authorized on this branch.

## Audit plan

1. Check anonymous HTTP access, robots.txt, response indexing directives and real 404s.
2. Read the advertised sitemap and its child maps. Compare coverage with archive shows, recordings, songs and media pages.
3. Inspect raw HTML for crawlable links and useful content without JavaScript.
4. Check titles, descriptions, canonical URLs, query variants and English/French alternate URLs.
5. Parse JSON-LD and check its entities and relationships against schema.org. Separate valid structured data from eligibility for Google rich results.
6. Check social metadata and image fallbacks.
7. Record confirmed gaps, unknowns and fixes in priority order, with verification criteria.

Initial audit scope: read-only public requests and source inspection. Local containers stayed stopped during the audit. Implementation and deployment were subsequently authorized; the isolated Ruby 4 container was restarted for testing. Search Console ownership, index coverage and ranking remain unknown without authenticated evidence.

## Findings

Live checks used anonymous HTTP requests, raw HTML parsing and XML parsing. The deployed plugin is `51cb91b`; no browser rendering was required to read archive content. Representative pages included the homepage, year listing, show, recording, song index, individual song, media index, French variants, a tracking URL, a missing show and a forum topic.

Captured metadata, robots rules and sitemap XML are in [discoverability-evidence.json](discoverability-evidence.json). This is a dated snapshot, not a complete crawl or a live monitoring report.

### What already works

- HTTPS pages return 200 without login. The missing show `/taper/1900-01-01` returns a real 404.
- `robots.txt` permits archive URLs for Googlebot and ordinary crawlers. No `noindex` meta tag or `X-Robots-Tag` was present on the sampled reader pages.
- Content, year navigation, show links, song links and recording links are in server-rendered HTML.
- Following the six year links from the homepage exposed all 176 show URLs returned by `/taper.json`, with none missing. Sitemap omission does not mean the current shows are orphaned. Googlebot-user-agent spot checks of the homepage and one show returned 200 without `noindex`.
- `/` and `/taper` consistently identify `/taper` as canonical. Two entry points are not automatically a problem when canonical signals agree.
- Sample show pages have useful titles, descriptions and parseable `MusicEvent` JSON-LD. `recordedIn` correctly connects an event to its recordings; the direction is valid schema.org vocabulary.
- Forum topics have their own canonical URLs and Discourse's normal social metadata.

### Confirmed gaps

| Priority | Finding | Evidence and consequence |
| --- | --- | --- |
| High | No archive sitemap coverage | `/robots.txt` advertises `/sitemap.xml`. Its two children, `/sitemap_recent.xml` and `/sitemap_1.xml`, contain 13 and 180 entries respectively, with **zero `/taper` URLs**. Topic coverage does not explicitly advertise archive show, recording, song or index URLs. |
| High | Canonical URLs retain arbitrary query parameters | `/taper?utm_source=audit` canonicals to itself. `ShowsController#band` preserves the entire query string. Tracking parameters and query ordering can create competing canonical URLs for identical content. |
| Medium | Empty filter pages remain indexable | `/taper?year=1900` returns 200 with a self-canonical despite having no shows. Define an explicit empty/invalid filter policy to avoid unlimited low-value listing URLs; keep valid populated year pages discoverable. |
| Medium | Language signals are inconsistent | `/taper?lang=fr` has `lang="fr"` and a French self-canonical, but `/taper/2026-09-12?lang=fr` canonicals to the unparameterized show. Language navigation has `hreflang` on anchors, but sampled pages have no reciprocal head links, HTTP alternate-language links or sitemap language annotations. |
| Medium | Missing descriptions | Year listings, media index, song index and recording detail have no description meta tag. Homepage, show and individual song descriptions exist. Show descriptions could identify the band and date as well as venue/setlist. |
| Medium | No archive social cards | No `og:*` or `twitter:*` tags on sampled Taper pages. `layouts/taper.html.erb` includes core's head partial but does not call `crawlable_meta_data`. A sampled forum topic falls back to the stock Discourse logo. |
| Medium | Structured data is narrow | Show JSON-LD exists, but recording pages lack recording/video entities. `/` emits core `WebSite` JSON-LD while its canonical `/taper` emits none. No standalone band entity or archive breadcrumb markup was observed. These are enrichment opportunities, not prerequisites for indexing. |
| Low | Homepage advertises the wrong Markdown alternate | The HTTP `Link` header on `/` points to `/latest.md`, which represents the forum topic list rather than the archive homepage. Audit core's homepage integration before adding an archive alternate. |
| Future | Large listings have hard limits | Source has a 500-show limit on the initial band query and a 300-item media limit. Confirm listing pagination/coverage behavior as collections grow. Do not assume a sitemap alone fixes missing navigation. |

`/sitemap_index.xml` returns 404, which is not a defect: the advertised sitemap index is `/sitemap.xml` and it works.

Topic and archive pages are separate useful representations: one is the discussion, the other is the music record. Decide their relationship explicitly; do not blanket-canonicalize all discussion topics to archive pages and discard their independent content.

## Implementation order and acceptance checks

1. **Archive sitemap integration.** Add public band, show, recording, song and media-index URLs through the supported core sitemap integration, or a dedicated sitemap advertised alongside core's. Use canonical absolute HTTPS URLs, real modification timestamps and bounded batches. Preserve core topic sitemaps. Test plugin-disabled, private category, hidden/deleted topic, deleted recording, multiple bands and sequence-suffixed show URLs. Private content must not appear in XML.
2. **Canonical and locale policy.** Keep meaningful filters such as year, venue and tour; normalize their values and ordering. Strip tracking and unknown query parameters. Decide a consistent explicit-language URL policy, then emit reciprocal EN/FR alternates and matching canonicals. Test cold anonymous requests, language cookies, homepage aliases and primary-band aliases.
3. **Page metadata.** Supply titles and descriptions for each reader page type using actual band/show/recording data. Reuse core social metadata with explicit canonical URL/title/description, a configured archive image fallback and recording thumbnails when available. Test escaped input, absent images, non-primary bands and localized text.
4. **Structured data.** Verify script-safe serialization with hostile imported strings before extending it. The current template uses `raw(...to_json)`; whether that is safe depends on the active JSON encoder and escaping configuration, so this audit does not establish an injection vulnerability. Add stable entity IDs and appropriate recording types, distinguishing video from audio. Consider `MusicGroup`, `CollectionPage` and breadcrumbs where supported by visible content. Keep event dates truthful and omit unavailable facts rather than inventing times, ticket offers or addresses. Parse JSON in request specs; run schema validation and Google's Rich Results Test separately. Valid schema does not promise a rich result, especially for historical shows.
5. **Production verification and indexing.** After implementation and deployment, rerun anonymous HTML/XML checks and compare sitemap coverage with the public archive. Verify Search Console ownership, submit the advertised sitemap and inspect representative URLs. Record Google's selected canonical and indexing exclusions. Search Console access and submission have not been verified or performed in this audit.

Request specs exercise generated responses rather than mirror helper implementation, including private content and hostile imported strings.

## Implementation

- Added `/taper/sitemap.xml` with paginated child maps for public shows, recordings, bands/indexes and songs. Robots.txt advertises it alongside the core sitemap. Permission checks are anonymous even for signed-in staff; disabled, private, login-required and no-index sites do not advertise it.
- Normalized canonical query parameters, consolidated reader locale code, added reciprocal EN/FR head links and kept French canonicals on French URLs. Empty filtered lists are `noindex,follow`; malformed years return 404.
- Added page descriptions, core Open Graph/Twitter metadata, YouTube thumbnails where available and the configured Discourse image fallback elsewhere.
- Added band, collection, website, breadcrumb and recording entities alongside show events. JSON is explicitly escaped for script embedding. Event/recording relationships use stable IDs. No unsupported event times or upload dates are invented.
- Removed the inaccurate forum Markdown alternate from the archive homepage.
- Applied the same visibility filtering to archive lists and song aggregation so hidden/private/deleted topics do not leak through discovery pages.

Validation: 159 backend examples and 9 browser examples passed on Discourse Ruby 4.0.9. RuboCop inspected 70 files without offenses; Syntax Tree formatting passed. The original live evidence remains a pre-change snapshot.

Remaining follow-ups: Search Console verification/submission and monitoring; an archive-specific social fallback image (the existing configured image is still used); large reader-list pagination beyond the existing 500-show/300-media limits; external rich-result validation. Sitemap pagination is implemented, but reader-list pagination is separate. No indexing or rich-result eligibility is claimed.

## Limits and sources

This is a discoverability audit, not proof of indexing or a ranking forecast. No authenticated Search Console data, field performance measurements or rich-result validator reports were available. Public requests with a Googlebot user agent can test response differences but cannot prove access from Google's real crawler infrastructure.

- [Google: build and submit a sitemap](https://developers.google.com/search/docs/crawling-indexing/sitemaps/build-sitemap)
- [Google: localized versions](https://developers.google.com/search/docs/specialty/international/localized-versions)
- [Google: event structured data](https://developers.google.com/search/docs/appearance/structured-data/event)
- [Schema.org: recordedIn](https://schema.org/recordedIn)

Source touchpoints: `plugin.rb`, `app/controllers/discourse_taper/shows_controller.rb`, `app/controllers/discourse_taper/recordings_controller.rb`, `app/controllers/discourse_taper/reader_locale.rb`, `app/views/layouts/taper.html.erb`, and `app/views/discourse_taper/shows/show.html.erb`.
