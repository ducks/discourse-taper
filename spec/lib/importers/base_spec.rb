# frozen_string_literal: true

describe DiscourseTaper::Importers::Base do
  let(:importer) { DiscourseTaper::Importers::ArchiveOrg.new(band: nil) }
  let(:url) { "https://archive.org/advancedsearch.php" }
  let(:success) { { status: 200, body: '{"ok":true}' } }

  let(:delays) { [] }

  before { allow(importer).to receive(:sleep) { |delay| delays << delay } }

  def fetch
    importer.send(:get_json, url)
  end

  it "honors Retry-After seconds before retrying a rate-limited request" do
    request =
      stub_request(:get, url).to_return({ status: 429, headers: { "Retry-After" => "7" } }, success)

    expect(fetch).to eq("ok" => true)
    expect(delays).to eq([7])
    expect(request).to have_been_requested.twice
  end

  it "honors an HTTP-date Retry-After on service unavailability" do
    freeze_time
    request =
      stub_request(:get, url).to_return(
        { status: 503, headers: { "Retry-After" => (Time.now + 30).httpdate } },
        success,
      )

    expect(fetch).to eq("ok" => true)
    expect(delays).to eq([30])
    expect(request).to have_been_requested.twice
  end

  [nil, "nonsense", "-1", "0", "1", "Wed, 01 Jan 2020 00:00:00 GMT"].each do |header|
    it "uses exponential backoff for Retry-After #{header.inspect}" do
      freeze_time Time.utc(2026, 11, 4)
      request =
        stub_request(:get, url).to_return(
          { status: 429, headers: header ? { "Retry-After" => header } : {} },
          { status: 429 },
          success,
        )

      expect(fetch).to eq("ok" => true)
      expect(delays).to eq([2, 4])
      expect(request).to have_been_requested.times(3)
    end
  end

  it "stops after three failed requests without a final sleep" do
    request = stub_request(:get, url).to_return(status: 429)

    expect { fetch }.to raise_error(DiscourseTaper::Error, /429/)
    expect(delays).to eq([2, 4])
    expect(request).to have_been_requested.times(3)
  end

  it "does not retry earlier than a Retry-After beyond the worker budget" do
    request = stub_request(:get, url).to_return(status: 429, headers: { "Retry-After" => "3600" })

    expect { fetch }.to raise_error(DiscourseTaper::Error, /429/)
    expect(delays).to eq([])
    expect(request).to have_been_requested.once
  end

  it "allows a Retry-After at the worker wait limit" do
    request =
      stub_request(:get, url).to_return(
        { status: 429, headers: { "Retry-After" => "60" } },
        success,
      )

    expect(fetch).to eq("ok" => true)
    expect(delays).to eq([60])
    expect(request).to have_been_requested.twice
  end

  [400, 401, 403, 404].each do |status|
    it "does not retry HTTP #{status}" do
      request = stub_request(:get, url).to_return(status: status, headers: { "Retry-After" => "2" })

      expect { fetch }.to raise_error(DiscourseTaper::Error, /#{status}/)
      expect(delays).to eq([])
      expect(request).to have_been_requested.once
    end
  end

  it "backs off on network failures and resets the attempt budget for the next request" do
    request =
      stub_request(:get, url)
        .to_timeout
        .then
        .to_return(success)
        .then
        .to_timeout
        .then
        .to_return(success)

    2.times { expect(fetch).to eq("ok" => true) }
    expect(delays).to eq([2, 2])
    expect(request).to have_been_requested.times(4)
  end
end
