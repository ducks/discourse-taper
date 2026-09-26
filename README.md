# discourse-taper

A live music archive for tapers, on Discourse. Shows are the primitive:
one performance, one topic. Recordings, videos, and archive.org items
attach to a show as sources, whether an importer found them or a person
did.

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
  Nothing becomes a record until a reviewer accepts it, so the archive
  is trustworthy whether a bot or a human found the item.
- **One suggestion per show.** Everything an importer finds for a date
  is filed as a single suggestion carrying every recording, with the
  venue chosen by majority spelling. A real archive.org collection has
  about five recordings per night and a dozen spellings of each venue,
  so proposing per item would flood the queue with duplicates. Re-runs
  append newly found recordings to the pending suggestion instead of
  proposing the show again, and a transient network fault retries the
  page rather than discarding the run.
- **Show-only sources.** setlist.fm knows the date, venue, city, tour,
  and songs of every show fans have logged, and nothing about tapes. Its
  importer proposes shows complete with setlists, and for a show a
  recording importer created first it proposes the setlist as a
  correction. A show keeps its setlist.fm id so it is never proposed
  twice.
- **Undated videos find their show.** YouTube titles carry dates in
  every format (5/8/77, 16/09/2026, September 16th, 16 septembre) or
  none at all. A slash date that reads two ways (10/05/2026) is settled by
  which reading lands on a known show. A video with no date is matched
  to a known or pending show whose venue or city it names: the one show
  there in the year the title gives, else the one in the month before
  the video was published, else the one show ever at that place; two
  candidates leave it undated rather than guessed. The search takes long
  videos only, so full sets rather than phone clips.
- **Venues resolve themselves, without a model.** Every spelling an
  importer sees for an accepted show is learned as an alias of that
  venue, so a reviewer answers "what is this venue" once, ever. An
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
4. Importers run every `taper_import_interval_hours`. A reviewer can
   kick one early with `POST /taper/suggestions/import`.

## API

| Route | Purpose |
| --- | --- |
| `GET /taper/bands` | Bands with show counts |
| `GET /taper` and `GET /taper/:band` | A band's shows, with year facets; filter by `year`, `venue`, `tour`. The short form is the primary band |
| `GET /taper/:date` and `GET /taper/:band/:date` | One show: setlist and sources. `-2` suffix for a second show that night |
| `POST /taper/suggest` and `POST /taper/:band/suggest` | Propose a `new_show`, `new_source`, or `correction` |
| `GET /taper/suggestions` | Pending queue (reviewers) |
| `POST /taper/suggestions/:id/accept` and `/reject` | Review |
| `POST /taper/suggestions/import` | Run an importer for a band now |

## Reader surface

`/taper` is a server-rendered site in the band's own look (ink on
paper, a mono face for every date, the three shapes), with no Ember app
underneath, so it is fast, cacheable, and indexable:

- **Front door**: the band name, one line of tagline (the band's
  description), headline counts, a bar per year from the first show to
  the latest with gap years shown as gaps, the latest shows, the newest
  recordings, and the band's `footer` (site policy, how to claim a
  tape) as paragraphs.
- **Year** (`?year=`), **venue** (`?venue=`), **tour** (`?tour=`): a
  monumental heading, counts, and the shows grouped by month with
  weekday dates. A venue or tour containing the word "festival" is
  marked as one.
- **Show**: the date as the headline, venue and city, runtime and tour,
  the numbered setlist with per-song notes, an embedded player for the
  first YouTube or archive.org recording, every recording with its
  taper (or "taper unclaimed"), previous and next, the two newest
  replies from the show's topic with a button into the forum, and
  MusicEvent structured data.

The reader renders in the site's own fonts and colours; a band's
identity belongs in a theme component (see Theming). Every path also
answers with `.json`. Anonymous
readers go through the anonymous cache. The reader strings are
translated to French (`server.fr.yml`); Discourse picks the locale
from the user or the browser.

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

## Not yet

- Direct audio upload. Sources come from archive.org and YouTube, which
  is where tapers already put recordings; hosting audio here is a
  storage decision deferred on purpose.

## Development

```sh
nix-shell
bundle install
bundle exec rubocop
bundle exec stree check $(git ls-files '*.rb') Gemfile
```

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
