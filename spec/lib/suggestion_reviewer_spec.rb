# frozen_string_literal: true

describe DiscourseTaper::SuggestionReviewer do
  fab!(:category)
  fab!(:reviewer, :admin)
  fab!(:member, :user)
  fab!(:band, :taper_band)

  before do
    SiteSetting.taper_enabled = true
    SiteSetting.taper_category_id = category.id
  end

  let(:reviewer_service) { described_class.new(reviewer: reviewer) }

  it "accepts a new_show suggestion into a topic plus record, with its source" do
    suggestion =
      DiscourseTaper::Suggestion.create!(
        kind: "new_show",
        band: band,
        origin: "archive_org",
        payload: {
          "date" => "1977-05-08",
          "venue" => "Barton Hall",
          "city" => "Ithaca",
          "external_id" => "gd1977-05-08.sbd",
          "setlist" => [{ "title" => "New Minglewood Blues" }, { "title" => "Loser" }],
          "sources" => [
            {
              "provider" => "archive_org",
              "external_id" => "gd1977-05-08.sbd",
              "url" => "https://archive.org/details/gd1977-05-08.sbd",
              "kind" => "soundboard",
              "format" => "flac",
              "taper_name" => "Betty Cantor",
            },
            {
              "provider" => "archive_org",
              "external_id" => "gd1977-05-08.aud",
              "url" => "https://archive.org/details/gd1977-05-08.aud",
              "kind" => "audience",
            },
          ],
        },
      )

    show = reviewer_service.accept!(suggestion, note: "looks right")

    expect(show).to be_persisted
    expect(show.topic.category).to eq(category)
    expect(show.topic.title).to include("Barton Hall")
    expect(show.topic.first_post.raw).to include("New Minglewood Blues")
    expect(show.setlist_titles).to eq(["New Minglewood Blues", "Loser"])
    expect(show.sources.count).to eq(2)
    expect(show.sources.first).to have_attributes(
      kind: "soundboard",
      format: "flac",
      taper_name: "Betty Cantor",
    )
    expect(suggestion.reload).to have_attributes(
      status: "accepted",
      reviewed_by: reviewer,
      review_note: "looks right",
    )
  end

  it "attaches a new_source to the matched show, and refuses when no show exists" do
    show = Fabricate(:taper_show, band: band, topic: Fabricate(:topic, category: category))
    suggestion =
      DiscourseTaper::Suggestion.create!(
        kind: "new_source",
        band: band,
        origin: "user",
        submitted_by: member,
        payload: {
          "date" => "1977-05-08",
          "url" => "https://youtube.com/watch?v=abc",
          "provider" => "youtube",
          "kind" => "video",
        },
      )

    expect(reviewer_service.accept!(suggestion)).to eq(show)
    source = show.sources.last
    expect(source.submitted_by).to eq(member)
    expect(source.kind).to eq("video")

    orphan =
      DiscourseTaper::Suggestion.create!(
        kind: "new_source",
        band: band,
        origin: "user",
        payload: {
          "date" => "1999-01-01",
          "url" => "https://example.com/x",
        },
      )
    expect { reviewer_service.accept!(orphan) }.to raise_error(DiscourseTaper::Error) { |e|
      expect(e.key).to eq("show_not_found")
    }
    expect(orphan.reload).to be_pending
  end

  it "accepts the missing-show form's single source and an importer's sources array alike" do
    from_form =
      DiscourseTaper::Suggestion.create!(
        kind: "new_show",
        band: band,
        origin: "user",
        submitted_by: member,
        payload: {
          "date" => "1972-08-27",
          "venue" => "Old Renaissance Faire Grounds",
          "source" => {
            "url" => "https://archive.org/details/gd72",
          },
        },
      )
    show = reviewer_service.accept!(from_form)
    expect(show.sources.count).to eq(1)
    expect(show.sources.first).to have_attributes(
      provider: "link",
      url: "https://archive.org/details/gd72",
      submitted_by: member,
    )
  end

  it "creates the venue on accept, learns every spelling, and links the show" do
    suggestion =
      DiscourseTaper::Suggestion.create!(
        kind: "new_show",
        band: band,
        origin: "archive_org",
        payload: {
          "date" => "2011-07-16",
          "venue" => "Bethel Woods Center for the Arts",
          "venue_spellings" => {
            "Bethel Woods Center for the Arts" => 14,
            "Bethel Woods" => 3,
            "Bethel Center For The Arts" => 1,
          },
          "city" => "Bethel",
          "region" => "NY",
        },
      )

    show = reviewer_service.accept!(suggestion)

    venue = DiscourseTaper::Venue.find_by!(name: "Bethel Woods Center for the Arts")
    expect(show.venue_record).to eq(venue)
    expect(venue).to have_attributes(city: "Bethel", region: "NY")
    expect(venue.aliases).to include("bethel woods", "bethel center for arts")

    # The next night at the same room resolves by alias, no reviewer needed.
    expect(DiscourseTaper::VenueResolver.new.resolve("Bethel Woods" => 1).venue).to eq(venue)
  end

  it "relinks the venue when a correction changes it" do
    show = Fabricate(:taper_show, band: band, venue: "MSG")
    suggestion =
      DiscourseTaper::Suggestion.create!(
        kind: "correction",
        band: band,
        show: show,
        origin: "user",
        payload: {
          "changes" => {
            "venue" => "Madison Square Garden",
          },
        },
      )

    reviewer_service.accept!(suggestion)
    show.reload
    expect(show.venue).to eq("Madison Square Garden")
    expect(show.venue_record.name).to eq("Madison Square Garden")
  end

  it "applies only allowed correction fields" do
    show = Fabricate(:taper_show, band: band, venue: "Barton Hal")
    suggestion =
      DiscourseTaper::Suggestion.create!(
        kind: "correction",
        band: band,
        show: show,
        origin: "user",
        payload: {
          "changes" => {
            "venue" => "Barton Hall",
            "tour" => "Spring 1977",
            "topic_id" => 999,
            "band_id" => 999,
          },
        },
      )

    reviewer_service.accept!(suggestion)
    show.reload
    expect(show.venue).to eq("Barton Hall")
    expect(show.tour).to eq("Spring 1977")
    expect(show.band).to eq(band)
  end

  it "credits a claimed recording to the member, once" do
    show = Fabricate(:taper_show, band: band, topic: Fabricate(:topic, category: category))
    source = Fabricate(:taper_source, show: show, provider: "youtube", taper_name: "DirtyMovies76")
    claim =
      DiscourseTaper::Suggestion.create!(
        kind: "claim",
        band: band,
        show: show,
        origin: "user",
        submitted_by: member,
        note: "That is my channel.",
        payload: {
          "source_id" => source.id,
        },
      )

    expect(reviewer_service.accept!(claim)).to eq(show)
    expect(source.reload).to have_attributes(taper: member, taper_name: "DirtyMovies76")
    expect(source.credited_taper).to eq(member.username)

    again =
      DiscourseTaper::Suggestion.create!(
        kind: "claim",
        band: band,
        show: show,
        origin: "user",
        submitted_by: Fabricate(:user),
        payload: {
          "source_id" => source.id,
        },
      )
    expect { reviewer_service.accept!(again) }.to raise_error(
      DiscourseTaper::Error,
      /already credited/,
    )
    expect(again.reload.status).to eq("pending")
  end

  it "does not learn a year or a label as a name for the place" do
    venue = DiscourseTaper::Venue.create!(name: "Le Grand Mix", city: "Tourcoing")
    venue.learn!(["2026", "HD", "4K", "Le Grand Mix Tourcoing"])
    expect(venue.aliases).to eq(["le grand mix", "le grand mix tourcoing"])
  end

  it "learns structured venue spellings when recordings are accepted" do
    show =
      Fabricate(
        :taper_show,
        band: band,
        date: Date.new(2026, 8, 14),
        venue: "Cottonwood Meadows",
        city: "Buena Vista",
        region: "CO",
        topic: Fabricate(:topic, category: category),
      )
    suggestion =
      DiscourseTaper::Suggestion.create!(
        kind: "new_source",
        band: band,
        show: show,
        origin: "archive_org",
        payload: {
          "date" => "2026-08-14",
          "venue" => "Field of Vision II Festival",
          "venue_spellings" => {
            "Field of Vision II Festival" => 2,
            "Field of Vision" => 1,
          },
          "sources" => [
            {
              "provider" => "youtube",
              "external_id" => "fov1",
              "url" => "https://youtu.be/fov1",
              "kind" => "video",
            },
          ],
        },
      )

    reviewer_service.accept!(suggestion)

    expect(show.reload.venue_record.name).to eq("Cottonwood Meadows")
    expect(show.venue_record.aliases).to include(
      "field of vision",
      "field of vision ii festival",
      "cottonwood meadows",
    )
  end

  [true, false].each do |linked|
    it "does not learn YouTube title fragments with an existing venue record: #{linked}" do
      venue = DiscourseTaper::Venue.create!(name: "ESMA", city: "Rennes") if linked
      venue&.learn!(["École ESMA"])
      show = Fabricate(:taper_show, band: band, venue: "ESMA", city: "Rennes", venue_record: venue)
      suggestion =
        DiscourseTaper::Suggestion.create!(
          kind: "new_source",
          origin: "youtube",
          band: band,
          show: show,
          payload: {
            "venue" => "Fabienk",
            "venue_spellings" => {
              "Yor Zarad" => 1,
              "Live Bristol Highlights" => 1,
            },
            "sources" => [
              {
                "provider" => "youtube",
                "external_id" => "kexp",
                "url" => "https://youtu.be/kexp",
                "title" => "Fabienk (Live on KEXP)",
              },
            ],
          },
        )

      reviewer_service.accept!(suggestion)

      expect(suggestion.reload.status).to eq("accepted")
      expect(show.sources.sole.external_id).to eq("kexp")
      expect(show.reload.venue).to eq("ESMA")
      expected = linked ? ["esma", "ecole esma"] : ["esma"]
      expect(show.venue_record.aliases).to contain_exactly(*expected)
    end
  end

  it "rejects, and refuses to review twice" do
    suggestion =
      DiscourseTaper::Suggestion.create!(
        kind: "new_show",
        band: band,
        origin: "user",
        payload: {
          "date" => "1977-05-08",
          "venue" => "X",
        },
      )
    reviewer_service.reject!(suggestion, note: "duplicate")
    expect(suggestion.reload).to have_attributes(status: "rejected", review_note: "duplicate")
    expect { reviewer_service.accept!(suggestion) }.to raise_error(DiscourseTaper::Error)
  end

  describe "individual recording review" do
    let(:sources) do
      %w[leeds lisbon].map do |id|
        {
          "provider" => "youtube",
          "external_id" => id,
          "url" => "https://youtu.be/#{id}",
          "title" => id,
        }
      end
    end
    let(:bundle) do
      DiscourseTaper::Suggestion.create!(
        kind: "new_show",
        band: band,
        origin: "youtube",
        submitted_by: member,
        payload: {
          "date" => "2026-10-18",
          "venue" => "O2 Academy Leeds",
          "sources" => sources,
          "external_id" => "leeds",
        },
      )
    end

    it "keeps the event separate and audits independent recording decisions" do
      rows = reviewer_service.split_recordings!(bundle)
      expect(rows.size).to eq(3)
      expect(bundle.reload.payload["sources"]).to eq([])
      expect(rows.drop(1).map { |s| s.payload["sources"].sole }).to eq(sources)
      expect(rows.drop(1).map(&:submitted_by)).to eq([member, member])
      expect(rows.drop(1).map { |s| s.payload["parent_suggestion_id"] }).to eq(
        [bundle.id, bundle.id],
      )
      show = reviewer_service.accept!(bundle)
      expect(show.sources).to be_empty
      rows[1].update!(show: show)
      reviewer_service.accept!(rows[1], note: "venue and date verified")
      reviewer_service.reject!(rows[2], note: "different city")
      expect(show.sources.pluck(:external_id)).to eq(["leeds"])
      expect(rows[1].reload.review_note).to eq("venue and date verified")
      expect(rows[2].reload.status).to eq("rejected")
    end

    it "splits an existing show's bundle without making another show" do
      show = Fabricate(:taper_show, band: band)
      bundle.update!(kind: "new_source", show: show)
      rows = reviewer_service.split_recordings!(bundle)
      expect(rows.size).to eq(2)
      expect(rows.map(&:show_id)).to eq([show.id, show.id])
      expect(rows.map { |s| s.payload["sources"].size }).to eq([1, 1])
      expect { reviewer_service.split_recordings!(bundle) }.not_to change(
        DiscourseTaper::Suggestion,
        :count,
      )
      reviewer_service.accept!(rows.first)
      expect(rows.last.reload).to be_pending
    end

    it "refuses to split an already reviewed bundle, including a stale instance" do
      stale = DiscourseTaper::Suggestion.find(bundle.id)
      reviewer_service.reject!(bundle)
      expect { reviewer_service.split_recordings!(stale) }.to raise_error(DiscourseTaper::Error)
      expect { reviewer_service.accept!(stale) }.to raise_error(DiscourseTaper::Error)
    end

    it "keeps isolated recordings out of importer append targets" do
      show = Fabricate(:taper_show, band: band, date: "2026-10-18")
      bundle.update!(kind: "new_source", show: show)
      reviewer_service.split_recordings!(bundle)
      importer = DiscourseTaper::Importers::Youtube.new(band: band)
      expect(
        importer.send(:pending_for, show.date, show, venue: show.venue, kind: "new_source"),
      ).to be_nil
    end
  end
end
