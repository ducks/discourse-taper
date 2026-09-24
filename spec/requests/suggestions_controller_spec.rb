# frozen_string_literal: true

describe DiscourseTaper::SuggestionsController do
  fab!(:category)
  fab!(:reviewers, :group)
  fab!(:reviewer, :user)
  fab!(:member, :user)
  fab!(:band, :taper_band)
  fab!(:suggestion) do
    DiscourseTaper::Suggestion.create!(
      kind: "new_show",
      band: band,
      origin: "archive_org",
      payload: {
        "date" => "1977-05-08",
        "venue" => "Barton Hall",
        "external_id" => "x",
      },
    )
  end

  before do
    SiteSetting.taper_enabled = true
    SiteSetting.taper_category_id = category.id
    SiteSetting.taper_reviewer_groups = reviewers.id.to_s
    reviewers.add(reviewer)
  end

  it "is closed to non-reviewers" do
    sign_in(member)
    get "/taper/suggestions.json"
    expect(response.status).to eq(403)
    post "/taper/suggestions/#{suggestion.id}/accept.json"
    expect(response.status).to eq(403)
  end

  it "lists pending suggestions for reviewers" do
    sign_in(reviewer)
    get "/taper/suggestions.json"
    expect(response.status).to eq(200)
    expect(response.parsed_body["suggestions"].map { |s| s["id"] }).to eq([suggestion.id])
  end

  it "accepts and returns the created show's url" do
    sign_in(reviewer)
    post "/taper/suggestions/#{suggestion.id}/accept.json", params: { note: "ok" }
    expect(response.status).to eq(200)
    expect(response.parsed_body["show_url"]).to eq("/taper/1977-05-08")
    expect(DiscourseTaper::Show.count).to eq(1)

    post "/taper/suggestions/#{suggestion.id}/accept.json"
    expect(response.status).to eq(422)
  end

  it "lets the reviewer correct the venue name on accept" do
    sign_in(reviewer)
    post "/taper/suggestions/#{suggestion.id}/accept.json",
         params: {
           venue: "Barton Hall, Cornell University",
         }
    expect(response.status).to eq(200)
    show = DiscourseTaper::Show.last
    expect(show.venue).to eq("Barton Hall, Cornell University")
    expect(show.venue_record.name).to eq("Barton Hall, Cornell University")
    expect(show.venue_record.aliases).to include("barton hall")
  end

  it "accepts every pending show from an importer in a job, ids fixed at request time" do
    sign_in(reviewer)
    other =
      DiscourseTaper::Suggestion.create!(
        kind: "new_show",
        band: band,
        origin: "setlist_fm",
        payload: {
          "date" => "1977-05-09",
          "venue" => "Buffalo Memorial Auditorium",
        },
      )
    DiscourseTaper::Suggestion.create!(
      kind: "new_source",
      band: band,
      origin: "setlist_fm",
      payload: {
        "date" => "1977-05-09",
        "url" => "https://example.com/tape",
      },
    )

    expect_enqueued_with(
      job: :taper_accept_suggestions,
      args: {
        suggestion_ids: [other.id],
        origin: "setlist_fm",
        reviewer_id: reviewer.id,
      },
    ) { post "/taper/suggestions/accept_all.json", params: { origin: "setlist_fm" } }
    expect(response.status).to eq(200)
    expect(response.parsed_body["queued"]).to eq(1)

    post "/taper/suggestions/accept_all.json", params: { origin: "nope" }
    expect(response.status).to eq(400)

    sign_in(member)
    post "/taper/suggestions/accept_all.json", params: { origin: "setlist_fm" }
    expect(response.status).to eq(403)
  end

  it "rejects" do
    sign_in(reviewer)
    post "/taper/suggestions/#{suggestion.id}/reject.json", params: { note: "dupe" }
    expect(response.status).to eq(200)
    expect(suggestion.reload).to have_attributes(status: "rejected", reviewed_by: reviewer)
  end

  it "serves the review page as the app shell to a browser" do
    sign_in(reviewer)
    get "/taper/review"
    expect(response.status).to eq(200)
    expect(response.media_type).to eq("text/html")
    expect(response.body).to include(%(rel="canonical" href="http://test.localhost/taper/review"))
  end

  it "queues an importer run for a band" do
    sign_in(reviewer)
    expect_enqueued_with(
      job: :taper_import_feed,
      args: {
        band_id: band.id,
        importer: "archive_org",
      },
    ) do
      post "/taper/suggestions/import.json", params: { band_id: band.id, importer: "archive_org" }
    end
    expect(response.status).to eq(200)
  end
end
