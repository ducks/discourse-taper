# frozen_string_literal: true

describe DiscourseTaper::Band do
  it "makes the first band primary and drops it from urls and titles" do
    main = Fabricate(:taper_band, name: "Grateful Dead")
    side = Fabricate(:taper_band, name: "Jerry Garcia Band")

    expect(main).to be_primary
    expect(side).not_to be_primary
    expect(main.url).to eq("/taper")
    expect(side.url).to eq("/taper/jerry-garcia-band")

    main_show = Fabricate(:taper_show, band: main, venue: "Barton Hall", city: "Ithaca")
    side_show = Fabricate(:taper_show, band: side, venue: "Keystone", city: "Berkeley")

    expect(main_show.url).to eq("/taper/1977-05-08")
    expect(main_show.title).to eq("1977-05-08 Barton Hall, Ithaca")
    expect(side_show.url).to eq("/taper/jerry-garcia-band/1977-05-08")
    expect(side_show.title).to eq("Jerry Garcia Band 1977-05-08 Keystone, Berkeley")
  end

  it "allows exactly one primary and can move it" do
    main = Fabricate(:taper_band, name: "Phish")
    side = Fabricate(:taper_band, name: "Trey Anastasio Band")

    expect { side.update!(primary: true) }.to raise_error(ActiveRecord::RecordInvalid)

    side.make_primary!
    expect(side.reload).to be_primary
    expect(main.reload).not_to be_primary
    expect(described_class.primary_band).to eq(side)
  end
end
