# discourse-taper

A live music archive built on Discourse. Collect shows, setlists and
recordings, then discuss each performance in its own topic. Importers check
**YouTube, Archive.org and setlist.fm**; reviewers decide which show and
recording suggestions belong in the archive.

Live example: [Archive de Poitrine](https://archive.depoitrine.com), an
Angine de Poitrine archive using Taper and a separate theme component.

## Import sources

| Source | What it imports | Configuration |
| --- | --- | --- |
| **setlist.fm** | Show dates, venues, cities, tours and setlists. Proposes new shows or missing-setlist corrections, not recordings. | Site setting `taper_setlistfm_api_key`; per-band `setlistfm_artist_name`, falling back to the band name. |
| **YouTube** | Live videos and clips from channel uploads or search; detected releases and press go to the media shelf. | Site setting `taper_youtube_api_key`; per-band `youtube_channel_id` and/or `youtube_search_query`. Optional scraping fallback uses `taper_youtube_scrape_enabled` and a search query. |
| **Archive.org** | Recordings and their metadata from an etree collection or a search across audio/video collections. | Per-band `archive_org_collection` or `archive_org_query`. No API key required. |

The built-in Discourse scheduler checks hourly and dispatches enabled importers
once `taper_import_interval_hours` has elapsed, **six hours by default**. No
separate cron job is needed. Importers propose changes rather than continuously
overwriting accepted records; setlist.fm IDs prevent already imported shows
from being proposed again.

## How it works

- **A show is a topic.** Band, date, venue, setlist, and every known
  source render in a card at the top of the topic. The replies are the
  community's memories and corrections. The archive category's
  permissions decide who can see the archive at all.
- **Two channels, one queue.** Importers walk archive.org (an etree
  collection, or a creator/title query across the community collections
  where the venue is read out of the title), YouTube channels and
  searches, and setlist.fm, and file what they find as *suggestions*. Members
  suggest shows, sources, and corrections through the same queue.
  New shows and recording suggestions wait for review by default. A band can
  opt into automatic acceptance of confidently dated recordings; detected
  media items are filed separately, as described below.
- **Review by band and date.** Importers can bundle recordings for a night,
  but reviewers can split them into individual suggestions and choose the
  performance each belongs to. Separate performances on the same date retain
  their own show IDs. Refreshes can append to unsplit bundles, but do not
  recombine recordings a reviewer has separated. See
  [Reviewing recordings individually](#reviewing-recordings-individually).
- **Show-only sources.** setlist.fm knows the date, venue, city, tour,
  and songs of every show fans have logged, and nothing about tapes. Its
  importer proposes shows complete with setlists, and for a show a
  recording importer created first it proposes the setlist as a
  correction. A show keeps its setlist.fm id so it is never proposed
  twice.
- **The search asks many ways.** A YouTube result page holds about
  twenty videos and every phrasing ranks them differently, so the
  scraper runs eleven phrasings (full set, full show, live, concert,
  concert complet, performance complète, festival, 4K, the bare name,
  interview, entrevue) plus "live YEAR" for every year the band has a
  show. It also searches the current and previous month without a
  duration filter to find recent clips. Asked six ways it missed a third
  of the full sets.
- **Releases stay out.** Searching for a band turns up its albums,
  singles, music videos, teasers, and podcast appearances next to the
  tapes. The YouTube and Archive.org importers run items through a release detector
  (title patterns in English and French, a numbered volume with no
  date, an undated upload on the band's own channel with no live cue)
  and file what it flags on the band's **media shelf** instead of the queue:
  albums, singles, official videos, promo, interviews, podcasts, each
  with a kind, the uploader, and a date. The shelf is at `/taper/media`
  (and `/taper/<band>/media`), by kind, with a strip of the newest on
  the front door. These items have no topic and bypass the suggestion queue;
  classification is heuristic, so a reviewer can hide an item and a re-run will not bring
  it back. The YouTube search adds "interview" and "entrevue" phrasings
  without the long-video filter to find press.
- **Undated videos find their show.** YouTube titles carry dates in
  every format (5/8/77, 16/09/2026, September 16th, 16 septembre) or
  none at all. A slash date that reads two ways (10/05/2026) is settled by
  which reading lands on a known show. A video with no date is matched
  to a known or pending show whose venue or city it names: the one show
  there in the year the title gives, else the one in the month before
  the video was published, else the one show ever at that place; two
  candidates leave it undated rather than guessed. Venue and venue-alias
  matches take priority over city matches. Most searches favor full sets;
  the month-specific searches also find shorter recordings.
- **Venues resolve themselves, without a model.** Venue spellings from
  structured imports are learned as aliases when accepted. YouTube title
  fragments are excluded: accepting a recording does not confirm its
  extracted venue text as an alias. Existing aliases still help the place
  matcher find undated festival videos. An
  importer resolves a night's spellings by learned alias first, then the
  abbreviations every taper uses (MSG, SPAC, Red Rocks), then a trigram
  near-match through PostgreSQL's `pg_trgm`, which must also agree on the
  venue's first word so "Mann Center" never becomes "Saratoga Performing
  Arts Center" on a shared word. Anything unresolved falls back to the
  most common spelling, and the queue shows how a venue was matched and
  lets the reviewer correct the name before accepting; the corrected
  spelling is learned too.
- **Matching.** An importer hit or a suggestion resolves to an existing
  show by band and date, with venue breaking ties when there were two
  shows that night. That is what lets a taper's upload and an archive.org
  item for the same night land on the same show.

## Bands

A site is usually "the X archive" with side projects alongside it. The
first band created becomes the **primary** band: it drops out of URLs,
show titles, and the topic card, so a single-band site never sees the
concept. Its shows live at `/taper/1977-05-08`; any other band's at
`/taper/<slug>/1977-05-08`. Move the primary with `band.make_primary!`.

## Setup

1. Enable `taper_enabled` and set `taper_category_id` to the category
   that holds show topics. To make the archive the site's front page,
   pick "Live archive" in `default_homepage`: `/` then serves the front
   door as a full page (`/taper` stays canonical), visitors who cannot
   see the archive category get the usual homepage, and the reader's
   "forum" links point at the first top-menu list instead of `/`.
2. Add reviewer groups to `taper_reviewer_groups`. Staff always can.
3. Create bands at `/taper/admin/bands` with an
   `archive_org_collection` (an etree collection) or an
   `archive_org_query` (for a band whose tapes sit in the community
   collections, e.g. `creator:("Band") OR title:("Band")`), a
   `youtube_channel_id`, a
   `youtube_search_query` (for tapes scattered across fans' channels),
   and/or a `setlistfm_artist_name` (defaults to the band name). Set
   `taper_youtube_api_key` to enable the YouTube importer (or, with no
   key, `taper_youtube_scrape_enabled` to read YouTube's search result
   pages instead: brittle, and not something YouTube's terms allow) and
   `taper_setlistfm_api_key` (free at setlist.fm/settings/api) to enable
   the setlist.fm one.
4. Review suggestions at `/taper/review`. Keep `auto_accept_recordings`
   off on the band unless you want confidently dated recordings attached
   automatically. New shows, corrections and ownership claims still need review.
5. Leave the six-hour import interval or change `taper_import_interval_hours`
   (1-168 hours). A reviewer can trigger an import early with
   `POST /taper/suggestions/import`, passing `band_id` and `importer`
   (`setlist_fm`, `youtube` or `archive_org`).

Importer GET requests make at most three attempts on network failures or HTTP
429/503, with exponential waits of 2 and 4 seconds. [Retry-After](https://www.rfc-editor.org/rfc/rfc9110.html#name-retry-after) accepts seconds
or an HTTP date and can extend that wait. A requested wait over 60 seconds stops
the run rather than retrying early or occupying a worker for a long period.
Other HTTP errors are not retried. setlist.fm waits one second between pages.
These limits apply per request/run; they do not coordinate concurrent imports
or schedule a deferred retry after a long cooldown.

## API

| Route | Purpose |
| --- | --- |
| `GET /taper/bands` | Bands with show counts |
| `GET /taper` and `GET /taper/:band` | A band's shows, with year facets; filter by `year`, `venue`, `tour`. The short form is the primary band |
| `GET /taper/:date` and `GET /taper/:band/:date` | One show: setlist and sources. `-2` suffix for a second show that night |
| `POST /taper/suggest` and `POST /taper/:band/suggest` | Propose a `new_show`, `new_source`, or `correction` |
| `GET /taper/media` and `/taper/:band/media` | Media shelf |
| `GET /taper/songs` and `/taper/:band/songs` | Song index; append `/:song` for performance history |
| `GET /taper/recordings/:id` | Recording detail |
| `PUT /taper/recordings/:id` | Edit a recording (reviewers) |
| `POST /taper/recordings/:id/move` | Move a recording to another show of the same band (reviewers) |
| `DELETE /taper/recordings/:id` | Remove a recording and prevent re-import (reviewers) |
| `GET /taper/review` | Review UI |
| `GET /taper/suggestions.json` | Pending suggestions (reviewers) |
| `POST /taper/suggestions/:id/split.json` | Split a recording bundle into individual suggestions (reviewers) |
| `POST /taper/suggestions/:id/accept` and `/reject` | Review |
| `POST /taper/suggestions/import` | Run an importer for a band now (reviewers) |
| `POST /taper/suggestions/accept_all.json` | Enqueue a reviewer-requested bulk acceptance of matching pending suggestions |
| `GET /taper/sitemap.xml` | Public archive sitemap index |

Reader HTML pages also expose `.json` responses. Mutation endpoints require an
authenticated member or reviewer as appropriate; normal Discourse authentication
and CSRF rules apply.

## Reader surface

`/taper` serves Rails-rendered HTML in the site's theme. Public archive pages
contain their content and links without loading the Ember app; the reviewer
queue and band administration use Discourse's app.

- **Front door**: the band name, one line of tagline (the band's
  description), headline counts, a bar per year from the first show to
  the latest with gap years shown as gaps, the latest shows, the newest
  recordings, and the band's `footer` (site policy, how to claim a
  tape) as paragraphs.
- **Year** (`?year=`), **venue** (`?venue=`), **tour** (`?tour=`): a
  monumental heading, counts, and the shows grouped by month with
  weekday dates. A venue or tour containing the word "festival" is
  marked as one.
- **Songs** (`/songs`, `/songs/<song>`): every song the setlists
  mention, by how often it was played, with first and last night, how
  often it opened or closed a set or came as an encore, and a page per
  song listing every night with its position in the set. Built from the
  setlists on request, so it is as right as they are; a song played from
  tape is not counted. The front door shows the five most played.
- **Show**: the date as the headline, venue and city, runtime and tour,
  the numbered setlist with per-song notes, an embedded player for the
  first YouTube or archive.org recording, every recording with its
  taper (or "taper unclaimed"), previous and next, the two newest
  replies from the show's topic with a button into the forum, and
  MusicEvent structured data.

The reader renders in the site's own fonts and colours; a band's
identity belongs in a theme component (see Theming). Reader data also
answers with `.json`. Eligible anonymous listing and show requests use the
anonymous cache; recording detail pages use `private, no-store`. The reader strings are
translated to French (`server.fr.yml`). Discourse picks the locale
from the user or the browser, and the reader's top bar offers a switch
(`?lang=fr`, remembered in a cookie for a year) between every locale
the plugin ships a server locale file for. Pages read under a chosen
language skip the anonymous cache.

Bands are managed at `/taper/admin/bands` (reviewers; also in the
sidebar): name, slug, tagline, front-door footer, and the archive.org
collection or query, YouTube channel id and search query, and
setlist.fm artist name the importers use. A band can be made primary
there, and deleted while it has no shows. The same fields are a JSON
API under the same path.

Every show page links to a suggestion form (`/taper/suggest?date=…`)
with a recording form and a correction form; the listing links to a
missing-show form. Plain HTML forms, no JavaScript, logged-in members
only; submissions land in the review queue.

## Sorting reader pages

Reader lists have a **Sort by** selector and an **Apply** button. These submit
normal GET requests, preserve active filters and language, and work without
JavaScript. The selected order is shareable through `?sort=` and is also used
by the corresponding `.json` response.

| Page | Sort values | Default |
| --- | --- | --- |
| Show lists, including year/venue/tour filters | `newest`, `oldest` | Newest performance first |
| Individual song's performance history | `newest`, `oldest` | Newest performance first |
| Song index | `most_played`, `least_played`, `title`, `recently_played` | Most played |
| Media shelf | `newest`, `oldest`, `title` | Newest publication first; undated items last |
| Recordings on a show | `added_oldest`, `added_newest`, `title` | First added |

The homepage keeps its latest-show preview and links to **Browse all shows**.
Media remains grouped by kind, with sorting applied within each group. A song's
first/last performance facts stay chronological regardless of the selected
display order. Sort-only variants share the same canonical URL.

## Search and sharing

- `/taper/sitemap.xml` lists paginated sitemaps for public shows, recordings,
  bands, song pages and archive indexes. `robots.txt` advertises it alongside
  Discourse's topic sitemap when indexing and sitemaps are enabled. Private,
  disabled and login-required archives do not expose the archive sitemap.
- Archive listings, song aggregation and sitemaps exclude hidden, deleted,
  private and personal-message topics from anonymous discovery.
- Canonical URLs retain meaningful year, venue and tour filters while dropping
  tracking parameters. Empty filtered pages use `noindex,follow`; malformed
  years return 404.
- English/French alternate links and language-aware canonicals identify the
  reader translations.
- Reader pages include descriptions and Open Graph/Twitter metadata. Eligible
  YouTube show/recording pages use video thumbnails; other pages use the
  site's configured social-image fallback.
- JSON-LD describes bands, shows, recordings, collections and breadcrumbs.
  Imported text is escaped for script embedding.

A sitemap makes URLs available to crawlers; it does not guarantee indexing or
rich results. Site owners still need to verify their search-console accounts,
submit the sitemap and monitor indexing. The implementation and audit are
recorded in [docs/discoverability-audit.md](docs/discoverability-audit.md).

## Managing recordings

Every recording has its own page at `/taper/recordings/<id>`, linked
from the show, with the player, the lineage, and the credit. Reviewers
see a management section there: fix the title, kind, format, taper, or
link; move the recording to another night of the same band; or remove
it. Removing leaves a rejected suggestion behind so the importer that
found it will not bring it back. Rejecting a suggestion in the queue has
the same effect: a reviewer's no is final for the importers.

A band can opt in to **attaching recordings without review**
(`auto_accept_recordings`, on the band admin page): when every
recording found for a night carries its date in its own title or
identifier and that show already exists, it is attached outright, with
a note saying so. Proposed shows, recordings whose date was inferred
from a description or a place name, corrections, and claims always wait
for a reviewer.

## Claiming a tape

Recordings arrive credited to whatever the source said: an archive.org
taper field, a YouTube channel name, or nothing. A signed-in member can
claim a recording from its show page ("Claim this tape"), say how the
reviewers can tell it is theirs, and a reviewer accepts or rejects it
in the queue like anything else. Accepted, the recording is credited to
the member's account and links to their profile; the imported name is
kept underneath. A recording credited to an account cannot be claimed
again.

## Not yet

- A direct audio-upload workflow. Recording links can already be submitted,
  but hosting tapes here needs a separate storage decision.
- Pagination for large reader listings beyond the current 500-show and
  300-media-item limits. Sitemap pages are already paginated.

## Development

```sh
nix-shell
bundle install
bundle exec rubocop
bundle exec stree check $(git ls-files '*.rb') Gemfile
```

The latest deployed changes were tested against Discourse on Ruby 4.0.9:
159 backend examples and nine browser examples passed. Run plugin specs from a
Discourse checkout with the plugin installed and its test database prepared:

```sh
LOAD_PLUGINS=1 RAILS_ENV=test bundle exec rspec plugins/discourse-taper/spec/lib plugins/discourse-taper/spec/models plugins/discourse-taper/spec/requests plugins/discourse-taper/spec/jobs
LOAD_PLUGINS=1 RAILS_ENV=test bundle exec rspec plugins/discourse-taper/spec/system
```

The standalone `shell.nix` supplies Ruby 3.3 for plugin lint tooling; it does not
select the Ruby version of the Discourse host.

## Theming

The plugin is generic; a site's identity goes in a theme component,
which the reader pages load through the normal theme pipeline along
with the theme's `head_tag` and `body_tag` (that is how a component adds
a web-font link). Everything a theme might want to change is a hook on
`body.taper`:

| Hook | Default |
| --- | --- |
| `--taper-display`, `--taper-display-weight` | The site heading font, 800 |
| `--taper-body`, `--taper-mono` | The site body font, the site monospace font |
| `--taper-paper`, `--taper-ink`, `--taper-ink-soft`, `--taper-mid`, `--taper-rule`, `--taper-well` | The colour scheme's secondary and primary shades |
| `--taper-accent`, `--taper-accent-soft` | The scheme's tertiary |
| `--taper-now-mark` | The glyph beside the current year's bar |
| `.taper-masthead__field` | An empty band above the band name, hidden until a theme fills it |
| `.taper-mark` | The inline mark before a tape count and on buttons, a dot by default |
| `.taper-source-mark` | The mark leading every recording, a square by default, with three `<i>` children for a theme that wants a shape |
| `.taper-player` | The embedded player's frame |

[archive-de-poitrine-theme](https://github.com/ducks/archive-de-poitrine-theme)
is the reference: polka dots, cubes, triangles, Bricolage Grotesque and
IBM Plex, one red.

## Reviewing recordings individually

The review queue groups suggestions by band and performance date. A date is a
review grouping, not a unique show key: separate performances on the same day
keep their own show IDs.

Use **Review recordings individually** on a bundle to separate its recordings.
For a proposed show, the event stays pending without recordings; create it first
or choose an existing performance for each recording. Each recording can then
be accepted or rejected with its own review note. Import refreshes do not append
to these individual suggestions. Nothing is approved just by splitting it.

Reviewer-authenticated API clients use `POST /taper/suggestions/:id/split.json`.
The response contains the pending suggestions, with `review_date` and IDs in
`nearby_shows`. Accept an individual recording with
`POST /taper/suggestions/:id/accept.json`, passing `show_id` and an evidence
`note`; reject it through the existing `/reject.json` endpoint. Show targets must
belong to the same band. Split children retain `parent_suggestion_id`, recording
metadata and submitter credit. This supports externally assisted review without
a model dependency or an unattended approval policy in the plugin.
