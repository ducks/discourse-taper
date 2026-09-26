# frozen_string_literal: true

describe "Taper band admin" do
  fab!(:category)
  fab!(:reviewers, :group)
  fab!(:reviewer, :user)
  fab!(:band) { Fabricate(:taper_band, name: "Angine de Poitrine", archive_org_collection: nil) }

  before do
    SiteSetting.taper_enabled = true
    SiteSetting.taper_category_id = category.id
    SiteSetting.taper_reviewer_groups = reviewers.id.to_s
    reviewers.add(reviewer)
    sign_in(reviewer)
  end

  it "edits a band's importer settings, adds a second band, moves primary, and deletes" do
    visit("/taper/admin/bands")

    form = find(".taper-band-form", text: "Angine de Poitrine")
    expect(form).to have_css(".taper-band-form__primary")
    form.find("[data-field='archive_org_query']").fill_in(with: 'creator:("Angine de Poitrine")')
    form.find("[data-field='description']").fill_in(with: "Every show since Saguenay, 2020.")
    form.find(".taper-band-form__save").click
    expect(form).to have_css(".taper-band-form__saved")
    expect(band.reload).to have_attributes(
      archive_org_query: 'creator:("Angine de Poitrine")',
      description: "Every show since Saguenay, 2020.",
    )

    find(".taper-bands__add").click
    new_form = find(".taper-band-form", text: "New band")
    new_form.find("[data-field='name']").fill_in(with: "Les Breastfeeders")
    new_form.find("[data-field='setlistfm_artist_name']").fill_in(with: "Les Breastfeeders")
    new_form.find(".taper-band-form__save").click

    expect(page).to have_css(".taper-band-form", count: 2)
    second = DiscourseTaper::Band.find_by(slug: "les-breastfeeders")
    expect(second).to have_attributes(primary: false, setlistfm_artist_name: "Les Breastfeeders")

    other = find(".taper-band-form", text: "Les Breastfeeders")
    other.find(".taper-band-form__make-primary").click
    expect(other).to have_css(".taper-band-form__primary")
    expect(find(".taper-band-form", text: "Angine de Poitrine")).to have_no_css(
      ".taper-band-form__primary",
    )
    expect(second.reload.primary).to eq(true)

    other.find(".taper-band-form__delete").click
    find(".dialog-footer .btn-danger").click
    expect(page).to have_css(".taper-band-form", count: 1)
    expect(DiscourseTaper::Band.exists?(second.id)).to eq(false)
  end

  it "offers the page in the sidebar to reviewers" do
    visit("/")
    expect(page).to have_css(".sidebar-section-link[data-link-name='taper-bands']", visible: :all)
  end
end
