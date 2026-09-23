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
- **Two channels, one queue.** Importers walk archive.org collections
  and YouTube channels and file what they find as *suggestions*. Members
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
   that holds show topics.
2. Add reviewer groups to `taper_reviewer_groups`. Staff always can.
3. Create bands (for now, from the Rails console) with an
   `archive_org_collection` and/or a `youtube_channel_id`. Set
   `taper_youtube_api_key` to enable the YouTube importer.
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

`/taper` is a server-rendered site: the show list by year, and a show
page with setlist, recordings, previous/next, a link into the
discussion, and MusicEvent structured data. Every path also answers
with `.json`. Anonymous readers go through the anonymous cache.

Bands are managed at `/taper/admin/bands` (reviewers): name,
description, and the archive.org collection or YouTube channel id the
importers use. Setting `primary` moves the primary band.

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
