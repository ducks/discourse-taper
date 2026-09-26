# frozen_string_literal: true

describe DiscourseTaper::RecordingsController do
  fab!(:category)
  fab!(:reviewers, :group)
  fab!(:reviewer, :user)
  fab!(:member, :user)
  fab!(:band) { Fabricate(:taper_band, name: "Angine de Poitrine") }
  fab!(:show) do
    Fabricate(
      :taper_show,
      band: band,
      date: Date.new(2026, 9, 16),
      venue: "Underground Arts",
      city: "Philadelphia",
      topic: Fabricate(:topic, category: category),
    )
  end
  fab!(:other_show) do
    Fabricate(
      :taper_show,
      band: band,
      date: Date.new(2026, 9, 17),
      venue: "Lincoln Theatre",
      city: "Washington",
      topic: Fabricate(:topic, category: category),
    )
  end
  fab!(:source) do
    Fabricate(
      :taper_source,
      show: show,
      provider: "youtube",
      external_id: "Wk_PLQuICx8",
      url: "https://www.youtube.com/watch?v=Wk_PLQuICx8",
      title: "Angine de Poitrine - Live (FULL SET) @ Underground Arts",
      kind: "video",
      format: "video",
      taper_name: "DirtyMovies76",
      duration_seconds: 4088,
    )
  end

  before do
    SiteSetting.taper_enabled = true
    SiteSetting.taper_category_id = category.id
    SiteSetting.taper_reviewer_groups = reviewers.id.to_s
    reviewers.add(reviewer)
  end

  it "has its own page, linked from the show, as html and json" do
    get "/taper/2026-09-16"
    expect(response.body).to include(%(href="/taper/recordings/#{source.id}"))

    get "/taper/recordings/#{source.id}"
    expect(response.status).to eq(200)
    expect(response.media_type).to eq("text/html")
    expect(response.body).to include("Angine de Poitrine - Live (FULL SET) @ Underground Arts")
    expect(response.body).to include("https://www.youtube-nocookie.com/embed/Wk_PLQuICx8")
    expect(response.body).to include("DirtyMovies76")
    expect(response.body).to include("1h 08m")
    expect(response.body).not_to include("Manage this recording")

    get "/taper/recordings/#{source.id}.json"
    expect(response.status).to eq(200)
    expect(response.parsed_body["recording"]).to include("id" => source.id, "kind" => "video")

    get "/taper/recordings/999999"
    expect(response.status).to eq(404)
  end

  it "lets a reviewer edit, move, and remove it, and keeps the importer from bringing it back" do
    sign_in(member)
    put "/taper/recordings/#{source.id}.json", params: { title: "nope" }
    expect(response.status).to eq(403)

    sign_in(reviewer)
    get "/taper/recordings/#{source.id}"
    expect(response.body).to include("Manage this recording")

    put "/taper/recordings/#{source.id}.json",
        params: {
          title: "Full set, Underground Arts",
          kind: "audience",
          taper_name: "TJ",
          recording_format: "flac",
        }
    expect(response.status).to eq(200)
    expect(source.reload).to have_attributes(
      title: "Full set, Underground Arts",
      kind: "audience",
      taper_name: "TJ",
      format: "flac",
    )

    post "/taper/recordings/#{source.id}/move.json", params: { date: "2026-09-17" }
    expect(response.status).to eq(200)
    expect(source.reload.show).to eq(other_show)

    post "/taper/recordings/#{source.id}/move.json", params: { date: "2026-09-18" }
    expect(response.status).to eq(404)

    delete "/taper/recordings/#{source.id}.json"
    expect(response.status).to eq(200)
    expect(DiscourseTaper::Source.exists?(source.id)).to eq(false)
    tombstone = DiscourseTaper::Suggestion.last
    expect(tombstone).to have_attributes(
      kind: "new_source",
      status: "rejected",
      show: other_show,
      reviewed_by: reviewer,
    )
    expect(tombstone.payload["sources"].first).to include(
      "provider" => "youtube",
      "external_id" => "Wk_PLQuICx8",
    )
  end
end
