require 'helper'
require 'flipper/cloud/configuration'
require 'flipper/adapters/instrumented'

RSpec.describe Flipper::Cloud::Configuration do
  let(:required_options) do
    { token: "asdf" }
  end

  it "can set token" do
    instance = described_class.new(required_options)
    expect(instance.token).to eq(required_options[:token])
  end

  it "can set instrumenter" do
    instrumenter = Object.new
    instance = described_class.new(required_options.merge(instrumenter: instrumenter))
    expect(instance.instrumenter).to be(instrumenter)
  end

  it "can set read_timeout" do
    instance = described_class.new(required_options.merge(read_timeout: 5))
    expect(instance.read_timeout).to eq(5)
  end

  it "can set open_timeout" do
    instance = described_class.new(required_options.merge(open_timeout: 5))
    expect(instance.open_timeout).to eq(5)
  end

  it "can set write_timeout" do
    instance = described_class.new(required_options.merge(write_timeout: 5))
    expect(instance.write_timeout).to eq(5)
  end

  it "can set sync_interval" do
    instance = described_class.new(required_options.merge(sync_interval: 1))
    expect(instance.sync_interval).to eq(1)
  end

  it "passes sync_interval into sync adapter" do
    # The initial sync of http to local invokes this web request.
    stub_request(:get, /flippercloud\.io/).to_return(status: 200, body: "{}")

    instance = described_class.new(required_options.merge(sync_interval: 1))
    expect(instance.adapter.synchronizer.interval).to be(1)
  end

  it "can set debug_output" do
    instance = described_class.new(required_options.merge(debug_output: STDOUT))
    expect(instance.debug_output).to eq(STDOUT)
  end

  it "defaults adapter block" do
    # The initial sync of http to local invokes this web request.
    stub_request(:get, /flippercloud\.io/).to_return(status: 200, body: "{}")

    instance = described_class.new(required_options)
    expect(instance.adapter).to be_instance_of(Flipper::Adapters::Sync)
  end

  it "can override adapter block" do
    # The initial sync of http to local invokes this web request.
    stub_request(:get, /flippercloud\.io/).to_return(status: 200, body: "{}")

    instance = described_class.new(required_options)
    instance.adapter do |adapter|
      Flipper::Adapters::Instrumented.new(adapter)
    end
    expect(instance.adapter).to be_instance_of(Flipper::Adapters::Instrumented)
  end

  it "can override url" do
    options = required_options.merge(url: "http://localhost:5000/adapter")
    instance = described_class.new(options)
    expect(instance.url).to eq("http://localhost:5000/adapter")

    instance = described_class.new(required_options)
    instance.url = "http://localhost:5000/adapter"
    expect(instance.url).to eq("http://localhost:5000/adapter")
  end

  it "raises ArgumentError for invalid sync_method" do
    expect {
      described_class.new(required_options.merge(sync_method: :foo))
    }.to raise_error(ArgumentError, "Unsupported sync_method. Valid options are (#<Set: {:poll, :webhook}>)")
  end

  it "defaults to poll for synchronizing" do
    memory_adapter = Flipper::Adapters::Memory.new
    instance = described_class.new(required_options)

    expect(instance.sync_method).to eq(:poll)
  end

  it "can use webhooks for synchronizing instead of polling" do
    memory_adapter = Flipper::Adapters::Memory.new
    instance = described_class.new(required_options.merge({
      sync_method: :webhook,
      local_adapter: memory_adapter,
    }))

    expect(instance.sync_method).to eq(:webhook)
    expect(instance.adapter).to be_instance_of(Flipper::Adapters::Memory)
  end

  it "can sync with cloud" do
    body = JSON.generate({
      "features": [
        {
          "key": "search",
          "state": "on",
          "gates": [
            {
              "key": "boolean",
              "name": "boolean",
              "value": true
            },
            {
              "key": "groups",
              "name": "group",
              "value": []
            },
            {
              "key": "actors",
              "name": "actor",
              "value": []
            },
            {
              "key": "percentage_of_actors",
              "name": "percentage_of_actors",
              "value": 0
            },
            {
              "key": "percentage_of_time",
              "name": "percentage_of_time",
              "value": 0
            }
          ]
        },
        {
          "key": "history",
          "state": "off",
          "gates": [
            {
              "key": "boolean",
              "name": "boolean",
              "value": false
            },
            {
              "key": "groups",
              "name": "group",
              "value": []
            },
            {
              "key": "actors",
              "name": "actor",
              "value": []
            },
            {
              "key": "percentage_of_actors",
              "name": "percentage_of_actors",
              "value": 0
            },
            {
              "key": "percentage_of_time",
              "name": "percentage_of_time",
              "value": 0
            }
          ]
        }
      ]
    })
    stub = stub_request(:get, "https://www.flippercloud.io/adapter/features").
      with({
        headers: {
          'Flipper-Cloud-Token'=>'asdf',
        },
      }).to_return(status: 200, body: body, headers: {})
    instance = described_class.new(required_options)
    instance.sync

    # Check that remote was fetched.
    expect(stub).to have_been_requested

    # Check that local adapter really did sync.
    local_adapter = instance.adapter.instance_variable_get("@local")
    all = local_adapter.get_all
    expect(all.keys).to eq(["search", "history"])
    expect(all["search"][:boolean]).to eq("true")
    expect(all["history"][:boolean]).to eq(nil)
  end
end
