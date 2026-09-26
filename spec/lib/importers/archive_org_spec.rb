# frozen_string_literal: true

describe DiscourseTaper::Importers::ArchiveOrg do
  fab!(:band) { Fabricate(:taper_band, archive_org_collection: "TestCollection") }

  before { SiteSetting.taper_import_page_size = 50 }

  def stub_search(docs)
    stub_request(:get, %r{https://archive\.org/advancedsearch\.php}).to_return(
      status: 200,
      headers: {
        "Content-Type" => "application/json",
      },
      body: { response: { docs: docs } }.to_json,
    )
  end

  def doc(
    identifier,
    venue: "Barton Hall",
    source: "SBD > reel > DAT",
    taper: "Betty Cantor",
    date: "1977-05-08"
  )
    {
      "identifier" => identifier,
      "title" => "Live at #{venue} on #{date}",
      "date" => "#{date}T00:00:00Z",
      "venue" => venue,
      "coverage" => "Ithaca, NY",
      "source" => source,
      "taper" => taper,
      "runtime" => "146:50.000",
    }
  end

  let(:sbd) { doc("gd1977-05-08.sbd.hicks") }

  it "files an unknown show as one new_show suggestion carrying its recordings" do
    stub_search([sbd])

    stats = described_class.new(band: band).run

    expect(stats).to eq(
      proposed: 1,
      matched: 0,
      corrected: 0,
      ignored: 0,
      accepted: 0,
      appended: 0,
      skipped: 0,
    )
    suggestion = DiscourseTaper::Suggestion.last
    expect(suggestion).to have_attributes(
      kind: "new_show",
      origin: "archive_org",
      status: "pending",
      band: band,
    )
    expect(suggestion.payload).to include(
      "date" => "1977-05-08",
      "venue" => "Barton Hall",
      "city" => "Ithaca",
      "region" => "NY",
    )
    expect(suggestion.payload["sources"].size).to eq(1)
    expect(suggestion.payload["sources"].first).to include(
      "provider" => "archive_org",
      "external_id" => "gd1977-05-08.sbd.hicks",
      "url" => "https://archive.org/details/gd1977-05-08.sbd.hicks",
      "kind" => "soundboard",
      "taper_name" => "Betty Cantor",
      "duration_seconds" => 8810,
    )
    expect(DiscourseTaper::Show.count).to eq(0)
  end

  it "groups every recording of one date into a single suggestion, choosing the majority venue" do
    stub_search(
      [
        doc("gd77.sbd", venue: "Utica Memorial Auditorium"),
        doc("gd77.aud1", venue: "Utica Memorial Auditorium", source: "dpa4021 > sd722", taper: nil),
        doc("gd77.aud2", venue: "Utica Auditorium", source: "schoeps mk4 > v3", taper: "Jim"),
      ],
    )

    stats = described_class.new(band: band).run

    expect(stats).to eq(
      proposed: 1,
      matched: 0,
      corrected: 0,
      ignored: 0,
      accepted: 0,
      appended: 0,
      skipped: 0,
    )
    suggestion = DiscourseTaper::Suggestion.last
    expect(suggestion.payload["venue"]).to eq("Utica Memorial Auditorium")
    expect(suggestion.payload["venue_match"]).to be_nil
    expect(suggestion.payload["venue_spellings"]).to eq(
      "Utica Memorial Auditorium" => 2,
      "Utica Auditorium" => 1,
    )
    expect(suggestion.payload["sources"].map { |s| s["external_id"] }).to eq(
      %w[gd77.sbd gd77.aud1 gd77.aud2],
    )
    # On etree an unmarked recording is an audience tape.
    expect(suggestion.payload["sources"].map { |s| s["kind"] }).to eq(
      %w[soundboard audience audience],
    )
  end

  it "expands a standard abbreviation before any venue exists" do
    stub_search([doc("gd77.sbd", venue: "MSG"), doc("gd77.aud", venue: "Madison Square Garden")])

    described_class.new(band: band).run

    payload = DiscourseTaper::Suggestion.last.payload
    expect(payload["venue"]).to eq("Madison Square Garden")
    expect(payload["venue_match"]).to include("method" => "abbreviation", "id" => nil)
  end

  it "resolves a known venue from any spelling and records how" do
    venue =
      DiscourseTaper::Venue.create!(
        name: "Bethel Woods Center for the Arts",
        city: "Bethel",
        region: "NY",
      )
    venue.learn!(["Bethel Woods"])
    stub_search(
      [
        doc("f1.sbd", venue: "Bethel Woods").merge("coverage" => nil),
        doc("f1.aud", venue: "bethel woods").merge("coverage" => nil),
      ],
    )

    described_class.new(band: band).run

    payload = DiscourseTaper::Suggestion.last.payload
    expect(payload["venue"]).to eq("Bethel Woods Center for the Arts")
    expect(payload["venue_match"]).to include("id" => venue.id, "method" => "alias", "score" => 1.0)
    expect(payload["venue_spellings"]).to eq("Bethel Woods" => 1, "bethel woods" => 1)
    # City and region come from the venue when the items lack them.
    expect(payload).to include("city" => "Bethel", "region" => "NY")
  end

  it "appends newly found recordings to the pending suggestion for that date" do
    stub_search([sbd])
    described_class.new(band: band).run
    stub_search([sbd, doc("gd1977-05-08.aud.cooper", source: "aud cassette", taper: "Jim Cooper")])

    stats = described_class.new(band: band).run

    expect(stats).to eq(
      proposed: 0,
      matched: 0,
      corrected: 0,
      ignored: 0,
      accepted: 0,
      appended: 1,
      skipped: 1,
    )
    expect(DiscourseTaper::Suggestion.count).to eq(1)
    expect(DiscourseTaper::Suggestion.last.payload["sources"].map { |s| s["external_id"] }).to eq(
      %w[gd1977-05-08.sbd.hicks gd1977-05-08.aud.cooper],
    )
  end

  it "files a known show's recordings as one new_source suggestion" do
    show = Fabricate(:taper_show, band: band, date: Date.new(1977, 5, 8), venue: "Barton Hall")
    stub_search([sbd, doc("gd1977-05-08.aud.cooper", source: "aud", taper: "Jim Cooper")])

    stats = described_class.new(band: band).run

    expect(stats).to eq(
      proposed: 0,
      matched: 1,
      corrected: 0,
      ignored: 0,
      accepted: 0,
      appended: 0,
      skipped: 0,
    )
    suggestion = DiscourseTaper::Suggestion.last
    expect(suggestion).to have_attributes(kind: "new_source", show: show)
    expect(suggestion.payload["sources"].size).to eq(2)
  end

  it "skips items already attached or already proposed, and items without a date" do
    show = Fabricate(:taper_show, band: band)
    Fabricate(
      :taper_source,
      show: show,
      provider: "archive_org",
      external_id: "gd1977-05-08.sbd.hicks",
    )
    undated = sbd.merge("identifier" => "mystery-tape", "title" => "A tape", "date" => nil)
    stub_search([sbd, undated])

    expect { described_class.new(band: band).run }.not_to change {
      DiscourseTaper::Suggestion.count
    }
  end

  describe "a band found by query across the community collections" do
    fab!(:band) do
      Fabricate(
        :taper_band,
        name: "Angine de Poitrine",
        archive_org_collection: nil,
        archive_org_query: 'creator:("Angine de Poitrine") OR title:("Angine de Poitrine")',
      )
    end

    def community(identifier, title, date: nil, mediatype: "audio", **extra)
      {
        "identifier" => identifier,
        "title" => title,
        "date" => date,
        "mediatype" => mediatype,
        "format" => ["Flac", "VBR MP3", "Metadata"],
      }.merge(extra)
    end

    it "searches by the query, not by collection, across audio and video" do
      stub_search([])
      described_class.new(band: band).run
      expect(
        a_request(:get, %r{https://archive\.org/advancedsearch\.php}).with do |req|
          q = CGI.parse(URI(req.uri).query)["q"].first
          q.include?('creator:("Angine de Poitrine")') &&
            q.include?("mediatype:(etree OR audio OR movies)") && !q.include?("collection:")
        end,
      ).to have_been_made
    end

    it "reads venue, city, and region out of the title when the item has no venue field" do
      stub_search(
        [
          community(
            "adp2026-08-19.mk4",
            "Angine de Poitrine - 2026-08-19 - The Independent, San Francisco, CA [AUD]",
            :date => "2026-08-19T00:00:00Z",
            "taper" => "TJ",
            "source" => "Schoeps MK4s > BabyNBox > Sony PCM-A10 > WAV",
            "runtime" => "68:51",
          ),
        ],
      )

      described_class.new(band: band).run

      payload = DiscourseTaper::Suggestion.last.payload
      expect(payload).to include(
        "date" => "2026-08-19",
        "venue" => "The Independent",
        "city" => "San Francisco",
        "region" => "CA",
      )
      expect(payload["sources"].first).to include(
        "kind" => "audience",
        "format" => "flac",
        "taper_name" => "TJ",
        "duration_seconds" => 4131,
      )
    end

    it "handles the looser title shapes tapers use" do
      stub_search(
        [
          community(
            "AngineDePoitrine2026-07-31",
            "Angine de Poitrine 2026-07-31 Newport Jazz Festival",
          ),
          community(
            "angine-de-poitrine-9-20-26",
            "Angine De Poitrine live in Richmond at Iron Blossom Festival 9/20/26",
            date: "2026-09-20T00:00:00Z",
          ),
          community(
            "adp-electric-ballroom",
            "Angine De Poitrine Live At Electric Ballroom 11.05.2026",
            "format" => ["VBR MP3"],
          ),
          community(
            "adp2026-09-01.dpa4061",
            "Angine de Poitrine - 2026-09-01 - Live Music Hall, Cologne, Germany [AUD]",
          ),
          community(
            "live-toronto-on-july-14-2026-rbc-amplitheatre",
            "Angine de Poitrine - Live - Toronto ON - July 14, 2026 - RBC Amplitheatre",
          ),
        ],
      )

      described_class.new(band: band).run

      by_date = DiscourseTaper::Suggestion.all.index_by { |s| s.payload["date"] }
      expect(by_date.keys).to contain_exactly(
        "2026-07-31",
        "2026-09-20",
        "2026-05-11",
        "2026-09-01",
        "2026-07-14",
      )
      expect(by_date["2026-09-01"].payload).to include(
        "venue" => "Live Music Hall",
        "city" => "Cologne",
        "region" => "Germany",
      )
      expect(by_date["2026-07-14"].payload).to include(
        "venue" => "RBC Amplitheatre",
        "city" => "Toronto ON",
      )
      expect(by_date["2026-07-31"].payload["venue"]).to eq("Newport Jazz Festival")
      expect(by_date["2026-09-20"].payload).to include(
        "venue" => "Iron Blossom Festival",
        "city" => "Richmond",
      )
      expect(by_date["2026-05-11"].payload["venue"]).to eq("Electric Ballroom")
      expect(by_date["2026-05-11"].payload["sources"].first["format"]).to eq("mp3")
    end

    it "ignores the band's releases and promo instead of proposing shows for them" do
      stub_search(
        [
          community(
            "angine-de-poitrine-vol.-1-album-integral",
            "Angine de Poitrine - Vol.1 (Full Album)",
            date: "2026-04-29T00:00:00Z",
            mediatype: "movies",
          ),
          community(
            "angine-de-poitrine-sherpa-official-cem-video",
            "Angine De Poitrine - Sherpa (Official CEM Video)",
            date: "2024-01-01T00:00:00Z",
            mediatype: "movies",
          ),
          community(
            "nwm-88-dynamic-duos-2",
            "No Words Music #88: Dynamic Duos Part 2 Featuring Angine de Poitrine",
            date: "2026-05-07T00:00:00Z",
          ),
          community(
            "adp2026-08-19.mk4",
            "Angine de Poitrine - 2026-08-19 - The Independent, San Francisco, CA [AUD]",
          ),
        ],
      )

      stats = described_class.new(band: band).run

      expect(stats).to include(ignored: 3, proposed: 1)
      expect(DiscourseTaper::Suggestion.count).to eq(1)
    end

    it "ignores an upload by the band itself that no title pattern catches" do
      stub_search(
        [
          community(
            "angine-de-poitrine-sherpa",
            "SHERPA - Angine De Poitrine",
            :date => "2024-06-01T00:00:00Z",
            "creator" => "Angine De Poitrine",
            "description" => "SHERPA by Angine De Poitrine, single release.",
          ),
        ],
      )

      expect(described_class.new(band: band).run).to include(ignored: 1, proposed: 0)
      expect(
        a_request(:get, %r{https://archive\.org/advancedsearch\.php}).with do |req|
          q = CGI.parse(URI(req.uri).query)["fl[]"]
          q.include?("creator") && q.include?("description")
        end,
      ).to have_been_made
    end

    it "files what it ignores on the band's media shelf, with a kind and the uploader" do
      stub_search(
        [
          community(
            "angine-de-poitrine-sherpa",
            "SHERPA - Angine De Poitrine",
            :date => "2024-06-01T00:00:00Z",
            "creator" => "Angine De Poitrine",
            "description" => "SHERPA by Angine De Poitrine, single release.",
          ),
          community(
            "nwm-88-dynamic-duos-2",
            "No Words Music #88: Dynamic Duos Part 2 Featuring Angine de Poitrine",
            :date => "2026-05-07T00:00:00Z",
            "creator" => "No Words Music",
          ),
        ],
      )

      described_class.new(band: band).run
      described_class.new(band: band).run

      items = DiscourseTaper::MediaItem.where(band: band).order(:external_id)
      expect(items.map { |i| [i.external_id, i.kind, i.channel, i.published_on&.iso8601] }).to eq(
        [
          ["angine-de-poitrine-sherpa", "single", "Angine De Poitrine", "2024-06-01"],
          ["nwm-88-dynamic-duos-2", "podcast", "No Words Music", "2026-05-07"],
        ],
      )
    end

    it "dates and places an item by its description when the title has neither, if it lands on a known show" do
      esma =
        Fabricate(
          :taper_show,
          band: band,
          date: Date.new(2025, 12, 4),
          venue: "ESMA",
          city: "Rennes",
        )
      stub_search(
        [
          community(
            "angine-de-poitrine-full-performance-live-on-kexp",
            "Angine de Poitrine - Full Performance (Live on KEXP)",
            :date => "2026-02-05T00:00:00Z",
            :mediatype => "movies",
            "creator" => ["Angine de Poitrine", "KEXP"],
            "description" =>
              "KEXP presents Angine de Poitrine performing live at ESMA in Rennes, France, during Trans Musicales 2025. Recorded December 04, 2025.",
          ),
        ],
      )

      stats = described_class.new(band: band).run

      expect(stats).to include(matched: 1, proposed: 0)
      suggestion = DiscourseTaper::Suggestion.last
      expect(suggestion).to have_attributes(kind: "new_source", show: esma)
      expect(suggestion.payload["sources"].first).to include(
        "date" => "2025-12-04",
        "kind" => "video",
      )
    end

    it "never re-proposes what a reviewer rejected" do
      stub_search(
        [
          community(
            "adp2026-08-19.mk4",
            "Angine de Poitrine - 2026-08-19 - The Independent, San Francisco, CA [AUD]",
          ),
        ],
      )
      described_class.new(band: band).run
      rejected = DiscourseTaper::Suggestion.last
      DiscourseTaper::SuggestionReviewer.new(reviewer: Fabricate(:admin)).reject!(
        rejected,
        note: "not them",
      )

      expect(described_class.new(band: band).run).to include(skipped: 1, proposed: 0)
      expect(DiscourseTaper::Suggestion.count).to eq(1)
    end

    it "attaches a dated recording of a known show outright when the band opted in, and still queues inferred ones" do
      band.update!(auto_accept_recordings: true)
      category = Fabricate(:category)
      SiteSetting.taper_category_id = category.id
      SiteSetting.taper_enabled = true
      Fabricate(
        :taper_show,
        band: band,
        date: Date.new(2026, 8, 19),
        venue: "The Independent",
        city: "San Francisco",
        topic: Fabricate(:topic, category: category),
      )
      Fabricate(
        :taper_show,
        band: band,
        date: Date.new(2026, 7, 31),
        venue: "Newport Jazz Festival",
        city: "Newport",
        topic: Fabricate(:topic, category: category),
      )
      stub_search(
        [
          community(
            "adp2026-08-19.mk4",
            "Angine de Poitrine - 2026-08-19 - The Independent, San Francisco, CA [AUD]",
            "taper" => "TJ",
          ),
          community(
            "undated-newport",
            "Angine de Poitrine at Newport Jazz Festival, full show",
            date: "2026-08-02T00:00:00Z",
          ),
        ],
      )

      stats = described_class.new(band: band).run

      expect(stats).to include(accepted: 1, matched: 1)
      attached = DiscourseTaper::Source.find_by(external_id: "adp2026-08-19.mk4")
      expect(attached).to have_attributes(taper_name: "TJ", provider: "archive_org")
      expect(DiscourseTaper::Suggestion.where(status: "accepted").count).to eq(1)
      expect(DiscourseTaper::Suggestion.pending.count).to eq(1)
    end

    it "prefers the date in the title over an upload date, and files video as video" do
      stub_search(
        [
          community(
            "adp2026-07-31.dmczs100.vid",
            "Angine de Poitrine - 2026-07-31 - Fort Adams State Park, Newport, RI, USA [VID]",
            date: "2026-08-02T00:00:00Z",
            mediatype: "movies",
          ),
          community(
            "angine-de-poitrine-vol.-1-album-integral",
            "Angine de Poitrine - Vol.1 (Full Album)",
            date: "2026-04-29T00:00:00Z",
            mediatype: "movies",
          ),
        ],
      )

      described_class.new(band: band).run

      # The album upload is a release, not a show, and is ignored outright.
      dates = DiscourseTaper::Suggestion.all.map { |s| s.payload["date"] }
      expect(dates).to contain_exactly("2026-07-31")
      newport = DiscourseTaper::Suggestion.find_by("payload->>'date' = '2026-07-31'")
      expect(newport.payload).to include(
        "venue" => "Fort Adams State Park",
        "city" => "Newport",
        "region" => "RI",
      )
      expect(newport.payload["sources"].first).to include("kind" => "video", "format" => "video")
    end
  end

  it "retries a page after a transient network fault instead of losing the run" do
    calls = 0
    stub_request(:get, %r{https://archive\.org/advancedsearch\.php}).to_return do
      calls += 1
      raise Timeout::Error, "DNS lookup timed out" if calls == 1
      {
        status: 200,
        headers: {
          "Content-Type" => "application/json",
        },
        body: { response: { docs: [sbd] } }.to_json,
      }
    end
    allow_any_instance_of(described_class).to receive(:sleep)

    stats = described_class.new(band: band).run

    expect(calls).to eq(2)
    expect(stats).to eq(
      proposed: 1,
      matched: 0,
      corrected: 0,
      ignored: 0,
      accepted: 0,
      appended: 0,
      skipped: 0,
    )
  end

  it "gives up after repeated faults" do
    stub_request(:get, %r{https://archive\.org/advancedsearch\.php}).to_raise(Timeout::Error)
    allow_any_instance_of(described_class).to receive(:sleep)

    expect { described_class.new(band: band).run }.to raise_error(Timeout::Error)
  end

  it "does not re-propose the same item on the next run" do
    stub_search([sbd])
    described_class.new(band: band).run
    stats = described_class.new(band: band).run
    expect(stats).to eq(
      proposed: 0,
      matched: 0,
      corrected: 0,
      ignored: 0,
      accepted: 0,
      appended: 0,
      skipped: 1,
    )
    expect(DiscourseTaper::Suggestion.count).to eq(1)
  end
end
