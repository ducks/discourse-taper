# frozen_string_literal: true

describe "Taper media shelf" do
  fab!(:category)
  fab!(:reviewers, :group)
  fab!(:reviewer, :user)
  fab!(:member, :user)
  fab!(:band) { Fabricate(:taper_band, name: "Angine de Poitrine") }
  fab!(:album) do
    DiscourseTaper::MediaItem.create!(
      band: band,
      provider: "archive_org",
      external_id: "angine-de-poitrine-vol.-ii-2026",
      url: "https://archive.org/details/angine-de-poitrine-vol.-ii-2026",
      title: "Angine de Poitrine - Vol. II (2026)",
      kind: "album",
      reason: "album",
      published_on: Date.new(2026, 4, 4),
    )
  end
  fab!(:interview) do
    DiscourseTaper::MediaItem.create!(
      band: band,
      provider: "youtube",
      external_id: "int1",
      url: "https://www.youtube.com/watch?v=int1",
      title: "Angine de Poitrine interview at Polaris 2026",
      kind: "interview",
      channel: "CBC Music",
      duration_seconds: 900,
      published_on: Date.new(2026, 9, 23),
    )
  end

  before do
    SiteSetting.taper_enabled = true
    SiteSetting.taper_category_id = category.id
    SiteSetting.taper_reviewer_groups = reviewers.id.to_s
    reviewers.add(reviewer)
  end

  it "lists the shelf by kind as html and json, and shows the newest on the front door" do
    get "/taper/media"
    expect(response.status).to eq(200)
    expect(response.media_type).to eq("text/html")
    expect(response.body).to include("Releases and media")
    expect(response.body).to include("Albums")
    expect(response.body).to include("Interviews")
    expect(response.body).to include("Angine de Poitrine interview at Polaris 2026")
    expect(response.body).to include("CBC Music · 15m")
    expect(response.body).not_to include("Hide")

    get "/taper/media.json"
    expect(response.status).to eq(200)
    expect(response.parsed_body["media"].map { |m| m["kind"] }).to eq(%w[interview album])

    get "/taper"
    expect(response.body).to include("From the band")
    expect(response.body).to include(%(href="/taper/media"))
    expect(response.body).to include("Angine de Poitrine - Vol. II (2026)")
  end

  it "lets a reviewer hide an item, and keeps it hidden" do
    sign_in(member)
    delete "/taper/admin/media/#{album.id}.json"
    expect(response.status).to eq(403)

    sign_in(reviewer)
    get "/taper/media"
    expect(response.body).to include("Hide")
    delete "/taper/admin/media/#{album.id}.json"
    expect(response.status).to eq(200)
    expect(album.reload.hidden).to eq(true)

    get "/taper/media.json"
    expect(response.parsed_body["media"].map { |m| m["id"] }).to eq([interview.id])

    DiscourseTaper::MediaItem.file!(
      band: band,
      provider: "archive_org",
      external_id: album.external_id,
      attributes: {
        url: album.url,
        title: album.title,
        kind: "album",
      },
    )
    expect(album.reload.hidden).to eq(true)
  end
end
