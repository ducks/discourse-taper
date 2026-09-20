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

  let(:doc) do
    {
      "identifier" => "gd1977-05-08.sbd.hicks",
      "title" => "Grateful Dead Live at Barton Hall on 1977-05-08",
      "date" => "1977-05-08T00:00:00Z",
      "venue" => "Barton Hall",
      "coverage" => "Ithaca, NY",
      "source" => "SBD > reel > DAT",
      "taper" => "Betty Cantor",
      "runtime" => "146:50.000",
    }
  end

  it "files an unknown show as a new_show suggestion carrying its source" do
    stub_search([doc])

    stats = described_class.new(band: band).run

    expect(stats).to eq(proposed: 1, matched: 0, skipped: 0)
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
    expect(suggestion.payload["source"]).to include(
      "provider" => "archive_org",
      "external_id" => "gd1977-05-08.sbd.hicks",
      "url" => "https://archive.org/details/gd1977-05-08.sbd.hicks",
      "kind" => "soundboard",
      "taper_name" => "Betty Cantor",
      "duration_seconds" => 8810,
    )
    expect(DiscourseTaper::Show.count).to eq(0)
  end

  it "files a known show's recording as a new_source suggestion" do
    show = Fabricate(:taper_show, band: band, date: Date.new(1977, 5, 8), venue: "Barton Hall")
    stub_search([doc])

    stats = described_class.new(band: band).run

    expect(stats).to eq(proposed: 0, matched: 1, skipped: 0)
    expect(DiscourseTaper::Suggestion.last).to have_attributes(kind: "new_source", show: show)
  end

  it "skips items already attached or already proposed, and items without a date" do
    show = Fabricate(:taper_show, band: band)
    Fabricate(
      :taper_source,
      show: show,
      provider: "archive_org",
      external_id: "gd1977-05-08.sbd.hicks",
    )
    undated = doc.merge("identifier" => "mystery-tape", "title" => "A tape", "date" => nil)
    stub_search([doc, undated])

    expect { described_class.new(band: band).run }.not_to change {
      DiscourseTaper::Suggestion.count
    }
  end

  it "does not re-propose the same item on the next run" do
    stub_search([doc])
    described_class.new(band: band).run
    expect { described_class.new(band: band).run }.not_to change {
      DiscourseTaper::Suggestion.count
    }
  end
end
