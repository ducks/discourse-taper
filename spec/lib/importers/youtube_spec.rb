# frozen_string_literal: true

describe DiscourseTaper::Importers::Youtube do
  fab!(:band) do
    Fabricate(
      :taper_band,
      name: "Angine de Poitrine",
      youtube_search_query: "Angine de Poitrine live",
    )
  end
  fab!(:category)

  before do
    SiteSetting.taper_enabled = true
    SiteSetting.taper_category_id = category.id
    SiteSetting.taper_youtube_api_key = "yt-key"
    SiteSetting.taper_import_page_size = 50
  end

  def hit(id, title, description: "", channel: "a fan", published: "2026-09-18T03:00:00Z")
    {
      "id" => {
        "kind" => "youtube#video",
        "videoId" => id,
      },
      "snippet" => {
        "title" => title,
        "description" => description,
        "channelTitle" => channel,
        "publishedAt" => published,
      },
    }
  end

  def stub_search(items, next_token: nil)
    body = { "items" => items }
    body["nextPageToken"] = next_token if next_token
    stub_request(:get, %r{https://www\.googleapis\.com/youtube/v3/search}).to_return(
      status: 200,
      headers: {
        "Content-Type" => "application/json",
      },
      body: body.to_json,
    )
  end

  def stub_durations(map)
    items = map.map { |id, iso| { "id" => id, "contentDetails" => { "duration" => iso } } }
    stub_request(:get, %r{https://www\.googleapis\.com/youtube/v3/videos}).to_return(
      status: 200,
      headers: {
        "Content-Type" => "application/json",
      },
      body: { "items" => items }.to_json,
    )
  end

  it "searches for the band, keeps only videos that name it, and reads durations" do
    stub_search(
      [
        hit(
          "Wk_PLQuICx8",
          "Angine de Poitrine - 9/16/26 - Underground Arts, Philadelphia (full set)",
        ),
        hit("noise01", "Angina pectoris explained by a cardiologist 9/16/26"),
      ],
    )
    stub_durations("Wk_PLQuICx8" => "PT1H12M9S", "noise01" => "PT12M")

    stats = described_class.new(band: band).run

    expect(stats).to eq(proposed: 1, matched: 0, corrected: 0, appended: 0, skipped: 0)
    suggestion = DiscourseTaper::Suggestion.last
    expect(suggestion.payload).to include(
      "date" => "2026-09-16",
      "venue" => "Underground Arts, Philadelphia (full set)",
    )
    expect(suggestion.payload["sources"]).to eq(
      [
        {
          "provider" => "youtube",
          "external_id" => "Wk_PLQuICx8",
          "url" => "https://www.youtube.com/watch?v=Wk_PLQuICx8",
          "title" => "Angine de Poitrine - 9/16/26 - Underground Arts, Philadelphia (full set)",
          "kind" => "video",
          "format" => "video",
          "taper_name" => "a fan",
          "duration_seconds" => 4329,
          "date" => "2026-09-16",
          "venue" => "Underground Arts, Philadelphia (full set)",
        },
      ],
    )
  end

  it "dates an undated video by the show it names, within a month of publishing" do
    Fabricate(
      :taper_show,
      band: band,
      date: Date.new(2026, 9, 16),
      venue: "Underground Arts",
      city: "Philadelphia",
      region: "PA",
    )
    DiscourseTaper::Suggestion.create!(
      kind: "new_show",
      band: band,
      origin: "setlist_fm",
      payload: {
        "date" => "2026-09-10",
        "venue" => "Le Poisson Rouge",
        "city" => "New York",
      },
    )
    stub_search(
      [
        hit(
          "philly",
          "Angine de Poitrine live at Underground Arts (full show)",
          published: "2026-09-18T03:00:00Z",
        ),
        hit(
          "lpr",
          "ANGINE DE POITRINE full set LPR NYC",
          description: "Le Poisson Rouge",
          published: "2026-09-12T03:00:00Z",
        ),
        hit("old", "Angine de Poitrine at Underground Arts", published: "2026-12-01T03:00:00Z"),
        hit("none", "Angine de Poitrine somewhere", published: "2026-09-18T03:00:00Z"),
      ],
    )
    stub_durations({})

    stats = described_class.new(band: band).run

    expect(stats).to eq(proposed: 0, matched: 1, corrected: 0, appended: 1, skipped: 2)
    matched = DiscourseTaper::Suggestion.find_by(kind: "new_source")
    expect(matched.payload["sources"].map { |s| s["external_id"] }).to eq(["philly"])
    pending = DiscourseTaper::Suggestion.find_by(origin: "setlist_fm")
    expect(pending.reload.payload["sources"].map { |s| s["external_id"] }).to eq(["lpr"])
  end

  it "walks channel uploads as well when the band has a channel" do
    band.update!(youtube_channel_id: "UCabc", youtube_search_query: nil)
    stub_request(:get, %r{https://www\.googleapis\.com/youtube/v3/channels}).to_return(
      status: 200,
      headers: {
        "Content-Type" => "application/json",
      },
      body: {
        "items" => [{ "contentDetails" => { "relatedPlaylists" => { "uploads" => "UUabc" } } }],
      }.to_json,
    )
    stub_request(:get, %r{https://www\.googleapis\.com/youtube/v3/playlistItems}).to_return(
      status: 200,
      headers: {
        "Content-Type" => "application/json",
      },
      body: {
        "items" => [
          {
            "snippet" => {
              "title" => "Newport Folk 2026-07-26 full set",
              "description" => "",
              "channelTitle" => "Angine de Poitrine",
              "publishedAt" => "2026-07-27T00:00:00Z",
              "resourceId" => {
                "videoId" => "J2OJDU9bZeQ",
              },
            },
          },
        ],
      }.to_json,
    )
    stub_durations("J2OJDU9bZeQ" => "PT58M")

    expect(described_class.new(band: band).run).to include(proposed: 1)
    expect(DiscourseTaper::Suggestion.last.payload["date"]).to eq("2026-07-26")
  end

  it "is unavailable without an api key" do
    SiteSetting.taper_youtube_api_key = ""
    expect(described_class.available?).to eq(false)
    expect(described_class.new(band: band).run[:proposed]).to eq(0)
  end
end
