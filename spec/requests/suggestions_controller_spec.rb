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
    expect(response.parsed_body["show_url"]).to eq("/taper/#{band.slug}/1977-05-08")
    expect(DiscourseTaper::Show.count).to eq(1)

    post "/taper/suggestions/#{suggestion.id}/accept.json"
    expect(response.status).to eq(422)
  end

  it "rejects" do
    sign_in(reviewer)
    post "/taper/suggestions/#{suggestion.id}/reject.json", params: { note: "dupe" }
    expect(response.status).to eq(200)
    expect(suggestion.reload).to have_attributes(status: "rejected", reviewed_by: reviewer)
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
