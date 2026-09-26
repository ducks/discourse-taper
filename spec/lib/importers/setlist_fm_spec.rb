# frozen_string_literal: true

describe DiscourseTaper::Importers::SetlistFm do
  fab!(:band) { Fabricate(:taper_band, name: "Angine de Poitrine") }
  fab!(:category)

  before do
    SiteSetting.taper_enabled = true
    SiteSetting.taper_category_id = category.id
    SiteSetting.taper_setlistfm_api_key = "test-key"
  end

  def setlist(
    id:,
    date:,
    venue: "Underground Arts",
    city: "Philadelphia",
    state: "PA",
    country: "United States",
    tour: "Vol. II",
    sets: nil
  )
    {
      "id" => id,
      "eventDate" => date,
      "artist" => {
        "name" => "Angine de Poitrine",
      },
      "venue" => {
        "name" => venue,
        "city" => {
          "name" => city,
          "stateCode" => state,
          "country" => {
            "code" => "US",
            "name" => country,
          },
        },
      },
      "tour" => {
        "name" => tour,
      },
      "sets" => {
        "set" =>
          sets ||
            [
              {
                "song" => [
                  {
                    "name" => "North American Scum",
                    "tape" => true,
                    "cover" => {
                      "name" => "LCD Soundsystem",
                    },
                  },
                  { "name" => "Angor" },
                  { "name" => "Sherpa", "info" => "closer" },
                ],
              },
              { "encore" => 1, "song" => [{ "name" => "Fabienk" }] },
            ],
      },
      "url" => "https://www.setlist.fm/setlist/x/#{id}.html",
    }
  end

  def stub_pages(*pages)
    total = pages.sum(&:size)
    pages.each_with_index do |setlists, index|
      stub_request(
        :get,
        %r{https://api\.setlist\.fm/rest/1\.0/search/setlists.*p=#{index + 1}(&|$)},
      ).with(headers: { "x-api-key" => "test-key", "Accept" => "application/json" }).to_return(
        status: 200,
        headers: {
          "Content-Type" => "application/json",
        },
        body: {
          "type" => "setlists",
          "itemsPerPage" => 20,
          "page" => index + 1,
          "total" => total,
          "setlist" => setlists,
        }.to_json,
      )
    end
  end

  it "is unavailable without an api key" do
    SiteSetting.taper_setlistfm_api_key = ""
    expect(described_class.available?).to eq(false)
    expect(described_class.new(band: band).run).to eq(
      proposed: 0,
      matched: 0,
      corrected: 0,
      ignored: 0,
      accepted: 0,
      appended: 0,
      skipped: 0,
    )
  end

  it "proposes a new show with venue, location, tour, and a flattened setlist" do
    stub_pages([setlist(id: "1b49d580", date: "16-09-2026")])

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
    expect(suggestion).to have_attributes(kind: "new_show", origin: "setlist_fm", band: band)
    expect(suggestion.payload).to include(
      "date" => "2026-09-16",
      "venue" => "Underground Arts",
      "city" => "Philadelphia",
      "region" => "PA",
      "country" => "United States",
      "tour" => "Vol. II",
      "setlistfm_id" => "1b49d580",
      "sources" => [],
    )
    expect(suggestion.payload["setlist"]).to eq(
      [
        { "title" => "North American Scum", "notes" => "from tape, LCD Soundsystem cover" },
        { "title" => "Angor" },
        { "title" => "Sherpa", "notes" => "closer" },
        { "title" => "Fabienk", "notes" => "encore" },
      ],
    )
  end

  it "fills in the setlist of a show that has none, and leaves one that has" do
    bare =
      Fabricate(
        :taper_show,
        band: band,
        date: Date.new(2026, 9, 16),
        venue: "Underground Arts",
        setlist: [],
      )
    full =
      Fabricate(
        :taper_show,
        band: band,
        date: Date.new(2026, 9, 10),
        venue: "Le Poisson Rouge",
        setlist: [{ "title" => "Angor" }],
      )
    stub_pages(
      [
        setlist(id: "a", date: "16-09-2026"),
        setlist(
          id: "b",
          date: "10-09-2026",
          venue: "Le Poisson Rouge",
          city: "New York",
          state: "NY",
        ),
      ],
    )

    stats = described_class.new(band: band).run

    expect(stats).to eq(
      proposed: 0,
      matched: 0,
      corrected: 1,
      ignored: 0,
      accepted: 0,
      appended: 0,
      skipped: 1,
    )
    correction = DiscourseTaper::Suggestion.find_by(kind: "correction")
    expect(correction.show).to eq(bare)
    expect(correction.payload.dig("changes", "setlist").map { |s| s["title"] }).to eq(
      ["North American Scum", "Angor", "Sherpa", "Fabienk"],
    )
    expect(correction.payload.dig("changes", "tour")).to eq("Vol. II")
    expect(DiscourseTaper::Suggestion.where(show: full)).to be_empty
  end

  it "walks every page and stops at the total" do
    stub_pages(
      [setlist(id: "p1", date: "16-09-2026")],
      [setlist(id: "p2", date: "10-09-2026", venue: "Le Poisson Rouge")],
    )
    allow_any_instance_of(described_class).to receive(:fetch_page).and_wrap_original do |m, *args|
      page = args[1]
      body = m.call(*args)
      body.merge("itemsPerPage" => 1, "total" => 2)
    end

    stats = described_class.new(band: band).run
    expect(stats[:proposed]).to eq(2)
  end

  it "never proposes a show it already imported or already proposed" do
    stub_pages([setlist(id: "1b49d580", date: "16-09-2026")])
    described_class.new(band: band).run
    expect(described_class.new(band: band).run[:skipped]).to eq(1)

    suggestion = DiscourseTaper::Suggestion.last
    show = DiscourseTaper::SuggestionReviewer.new(reviewer: Fabricate(:admin)).accept!(suggestion)
    expect(show.setlistfm_id).to eq("1b49d580")
    expect(described_class.new(band: band).run).to include(skipped: 1, proposed: 0)
  end
end
