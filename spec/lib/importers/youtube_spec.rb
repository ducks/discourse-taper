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

    expect(stats).to eq(proposed: 1, matched: 0, corrected: 0, ignored: 0, appended: 0, skipped: 0)
    suggestion = DiscourseTaper::Suggestion.last
    expect(suggestion.payload).to include(
      "date" => "2026-09-16",
      "venue" => "Underground Arts",
      "city" => "Philadelphia",
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
          "venue" => "Underground Arts",
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

    # "old" names Underground Arts with no date and long after the show;
    # the one show ever at that place is still the answer.
    expect(stats).to eq(proposed: 0, matched: 1, corrected: 0, ignored: 0, appended: 1, skipped: 1)
    matched = DiscourseTaper::Suggestion.find_by(kind: "new_source")
    expect(matched.payload["sources"].map { |s| s["external_id"] }).to contain_exactly(
      "philly",
      "old",
    )
    pending = DiscourseTaper::Suggestion.find_by(origin: "setlist_fm")
    expect(pending.reload.payload["sources"].map { |s| s["external_id"] }).to eq(["lpr"])
  end

  it "reads the venue and city out of an at-sign title" do
    stub_search(
      [
        hit(
          "lpr1",
          "Angine de Poitrine live in NYC @ le Poisson Rouge - Full set, night 1 - 09/09/26",
        ),
      ],
    )
    stub_durations("lpr1" => "PT1H18M")

    described_class.new(band: band).run

    expect(DiscourseTaper::Suggestion.last.payload).to include(
      "date" => "2026-09-09",
      "venue" => "le Poisson Rouge",
      "city" => "NYC",
    )
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

  describe "without an api key, reading result pages" do
    before do
      SiteSetting.taper_youtube_api_key = ""
      SiteSetting.taper_youtube_scrape_enabled = true
    end

    def renderer(
      id,
      title,
      length: "1:08:44",
      channel: "a fan",
      published: "2 weeks ago",
      snippet: ""
    )
      {
        "videoRenderer" => {
          "videoId" => id,
          "title" => {
            "runs" => [{ "text" => title }],
          },
          "lengthText" => {
            "simpleText" => length,
          },
          "ownerText" => {
            "runs" => [{ "text" => channel }],
          },
          "publishedTimeText" => {
            "simpleText" => published,
          },
          "detailedMetadataSnippets" => [
            { "snippetText" => { "runs" => [{ "text" => snippet }] } },
          ],
        },
      }
    end

    def results_page(renderers)
      data = {
        "contents" => {
          "sectionListRenderer" => {
            "contents" => [{ "itemSectionRenderer" => { "contents" => renderers } }],
          },
        },
      }
      "<html><script>var ytInitialData = #{data.to_json};</script></html>"
    end

    def stub_results(renderers)
      stub_request(:get, %r{https://www\.youtube\.com/results}).to_return(
        status: 200,
        headers: {
          "Content-Type" => "text/html",
        },
        body: results_page(renderers),
      )
    end

    it "is available, searches long videos for each phrasing, and reads duration and channel off the page" do
      expect(described_class.available?).to eq(true)
      stub_results(
        [
          renderer(
            "Wk_PLQuICx8",
            "Angine de Poitrine - Live (FULL SET) @ Underground Arts - Philadelphia, PA 9/16/26",
            channel: "DirtyMovies76",
          ),
        ],
      )

      stats = described_class.new(band: band).run

      expect(stats).to eq(
        proposed: 1,
        matched: 0,
        corrected: 0,
        ignored: 0,
        appended: 0,
        skipped: 0,
      )
      expect(
        a_request(:get, %r{https://www\.youtube\.com/results}).with do |req|
          q = CGI.parse(URI(req.uri).query)
          q["sp"] == ["EgIYAg=="] && q["search_query"].first.include?("Angine de Poitrine live")
        end,
      ).to have_been_made.times(4)
      source = DiscourseTaper::Suggestion.last.payload["sources"].first
      expect(source).to include(
        "external_id" => "Wk_PLQuICx8",
        "duration_seconds" => 4124,
        "taper_name" => "DirtyMovies76",
        "kind" => "video",
      )
      expect(DiscourseTaper::Suggestion.last.payload["date"]).to eq("2026-09-16")
    end

    it "settles a date that reads two ways by the show it lands on" do
      Fabricate(
        :taper_show,
        band: band,
        date: Date.new(2026, 5, 11),
        venue: "Electric Ballroom",
        city: "London",
      )
      stub_results(
        [
          renderer(
            "ballroom",
            "Angine de Poitrine - Live at Electric Ballroom, London, 11/05/2026",
          ),
        ],
      )

      stats = described_class.new(band: band).run

      expect(stats).to include(matched: 1, proposed: 0)
      expect(DiscourseTaper::Suggestion.last.payload["sources"].first["date"]).to eq("2026-05-11")
    end

    it "dates a video by the one show at the place it names in the year it gives, or ever" do
      Fabricate(
        :taper_show,
        band: band,
        date: Date.new(2026, 7, 31),
        venue: "Newport Jazz Festival",
        city: "Newport",
      )
      Fabricate(
        :taper_show,
        band: band,
        date: Date.new(2025, 8, 1),
        venue: "Newport Jazz Festival",
        city: "Newport",
      )
      Fabricate(
        :taper_show,
        band: band,
        date: Date.new(2026, 7, 26),
        venue: "Fuji Rock Festival",
        city: "Naeba",
      )
      Fabricate(
        :taper_show,
        band: band,
        date: Date.new(2026, 3, 3),
        venue: "La Lune des Pirates",
        city: "Amiens",
      )
      stub_results(
        [
          renderer(
            "newport",
            "Angine de Poitrine - Full Set - Live at Newport Jazz Festival, 2026",
            published: "1 month ago",
          ),
          renderer(
            "fuji",
            "4K Full Show : Angine de Poitrine in Fuji Rock 2026 Day 3",
            published: "2 months ago",
          ),
          renderer(
            "amiens",
            "Angine De Poitrine - La Lune Des Pirates - Amiens - Full Set",
            published: "6 months ago",
          ),
          renderer(
            "ambiguous",
            "Angine de Poitrine at Newport Jazz Festival full set",
            published: "11 months ago",
          ),
        ],
      )

      stats = described_class.new(band: band).run

      expect(stats).to include(matched: 3, skipped: 1)
      dates = DiscourseTaper::Suggestion.all.map { |s| s.payload["sources"].first["date"] }
      expect(dates).to contain_exactly("2026-07-31", "2026-07-26", "2026-03-03")
    end

    it "trusts a date in the description only when it lands on a known show" do
      Fabricate(
        :taper_show,
        band: band,
        date: Date.new(2026, 9, 16),
        venue: "Underground Arts",
        city: "Philadelphia",
      )
      stub_results(
        [
          renderer(
            "desc-known",
            "Angine de Poitrine full set in Philly",
            snippet: "Recorded 2026-09-16 at Underground Arts.",
          ),
          renderer(
            "desc-release",
            "Angine De Poitrine - Full Live Concert @ Québec 2025",
            snippet: "Filmed on 2024-06-01 in Québec City.",
          ),
        ],
      )

      stats = described_class.new(band: band).run

      expect(stats).to include(matched: 1, proposed: 0, skipped: 1)
      expect(DiscourseTaper::Suggestion.last.payload["sources"].first["external_id"]).to eq(
        "desc-known",
      )
    end

    it "ignores the band's own releases found by the search" do
      stub_results(
        [
          renderer(
            "album",
            "Angine de Poitrine - Vol.II (Official Complete Album)",
            channel: "Angine de Poitrine and Spectacles Bonzai",
          ),
          renderer(
            "own",
            "Angine de Poitrine - Sarniezz",
            channel: "Angine de Poitrine",
            length: "4:12",
          ),
          renderer(
            "kexp",
            "Angine de Poitrine - Full Performance (Live on KEXP)",
            channel: "KEXP",
            published: "8 months ago",
          ),
        ],
      )

      stats = described_class.new(band: band).run

      expect(stats).to include(ignored: 2)
      expect(DiscourseTaper::Suggestion.count).to eq(0)
    end

    it "is not available when neither a key nor scraping is enabled, and ignores a page with no data" do
      SiteSetting.taper_youtube_scrape_enabled = false
      expect(described_class.available?).to eq(false)

      SiteSetting.taper_youtube_scrape_enabled = true
      stub_request(:get, %r{https://www\.youtube\.com/results}).to_return(
        status: 200,
        body: "<html>consent</html>",
      )
      expect(described_class.new(band: band).run).to include(proposed: 0, skipped: 0)
    end
  end

  it "is unavailable without an api key" do
    SiteSetting.taper_youtube_api_key = ""
    SiteSetting.taper_youtube_scrape_enabled = false
    expect(described_class.available?).to eq(false)
    expect(described_class.new(band: band).run[:proposed]).to eq(0)
  end
end
