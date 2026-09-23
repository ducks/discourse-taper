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

## Not yet

- Direct audio upload for tapers (goes through UploadCreator; needs a
  decision on size limits and storage).
- A band admin UI; bands are console-created for now.
- A reader surface for browsing by year, venue, and tour outside the
  topic list.

## Development

```sh
nix-shell
bundle install
bundle exec rubocop
bundle exec stree check $(git ls-files '*.rb') Gemfile
```
