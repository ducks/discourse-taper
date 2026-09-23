# frozen_string_literal: true

describe DiscourseTaper::BandsController do
  fab!(:category)
  fab!(:reviewers, :group)
  fab!(:reviewer, :user)
  fab!(:member, :user)

  before do
    SiteSetting.taper_enabled = true
    SiteSetting.taper_category_id = category.id
    SiteSetting.taper_reviewer_groups = reviewers.id.to_s
    reviewers.add(reviewer)
  end

  it "is closed to non-reviewers" do
    sign_in(member)
    post "/taper/admin/bands.json", params: { name: "Nope" }
    expect(response.status).to eq(403)
  end

  it "creates, updates, moves primary, and refuses to delete a band with shows" do
    sign_in(reviewer)

    post "/taper/admin/bands.json",
         params: {
           name: "Grateful Dead",
           archive_org_collection: "GratefulDead",
         }
    expect(response.status).to eq(200)
    main = DiscourseTaper::Band.find(response.parsed_body["band"]["id"])
    expect(main).to have_attributes(
      slug: "grateful-dead",
      archive_org_collection: "GratefulDead",
      primary: true,
    )

    post "/taper/admin/bands.json", params: { name: "Jerry Garcia Band" }
    side = DiscourseTaper::Band.find(response.parsed_body["band"]["id"])
    expect(side).not_to be_primary

    put "/taper/admin/bands/#{side.id}.json", params: { youtube_channel_id: "UC123", primary: true }
    expect(response.status).to eq(200)
    expect(side.reload).to have_attributes(youtube_channel_id: "UC123", primary: true)
    expect(main.reload).not_to be_primary

    Fabricate(:taper_show, band: main)
    delete "/taper/admin/bands/#{main.id}.json"
    expect(response.status).to eq(422)
    expect(DiscourseTaper::Band.exists?(main.id)).to eq(true)

    delete "/taper/admin/bands/#{side.id}.json"
    expect(response.status).to eq(200)
    expect(DiscourseTaper::Band.exists?(side.id)).to eq(false)
  end
end
