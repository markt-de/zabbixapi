# The methods a resource class inherits from Basic unchanged: what they put on the wire and return.
RSpec.shared_examples 'an inherited create' do |options|
  let(:exchange) { JSON.parse(JSON.generate(options[:exchange])) }
  let(:client) { FakeClient.new([exchange]) }
  let(:resource) { described_class.new(client) }

  it 'wraps the payload in an Array, merged over the defaults' do
    resource.create(options[:payload])
    expect(client.sent("#{resource.method_name}.create")).to eq([[JSON.parse(JSON.generate(options[:defaults].merge(options[:payload])))]])
  end

  it 'returns the first id of the result as an Integer' do
    expect(resource.create(options[:payload])).to eq(exchange['result'][resource.keys][0].to_i)
  end
end

RSpec.shared_examples 'an inherited delete' do |options|
  let(:exchange) { JSON.parse(JSON.generate(options[:exchange])) }
  let(:client) { FakeClient.new([exchange]) }
  let(:resource) { described_class.new(client) }

  it 'sends the bare id inside an Array and returns the result id as an Integer' do
    expect(resource.delete(options[:id])).to eq(exchange['result'][resource.keys][0].to_i)
    expect(client.sent("#{resource.method_name}.delete")).to eq([[options[:id]]])
  end
end

RSpec.shared_examples 'an inherited get_id' do |options|
  let(:identify) { options[:identify] }
  let(:key) { options[:key] }
  let(:value) { options[:value] }
  let(:rows) { JSON.parse(JSON.generate(options[:rows])) }
  let(:object) { described_class.new(FakeClient.new).method_name }

  def client_answering(result)
    FakeClient.new([{ method: "#{object}.get", params: {}, result: result }])
  end

  it 'filters on the identify value and asks for the id and identify only' do
    client = client_answering(rows)
    described_class.new(client).get_id(identify.to_sym => value)
    expect(client.sent("#{object}.get").first).to eq('filter' => { identify => value }, 'output' => [key, identify])
  end

  it 'returns the matching id as an Integer' do
    expect(described_class.new(client_answering(rows)).get_id(identify.to_sym => value)).to eq(rows.first[key].to_i)
  end

  it 'returns nil when nothing matches' do
    expect(described_class.new(client_answering([])).get_id(identify.to_sym => value)).to be_nil
  end

  it 'raises before any request without the identify value' do
    client = client_answering(rows)
    expect { described_class.new(client).get_id({}) }.to raise_error(ZabbixApi::ApiError, /#{identify} not supplied/)
    expect(client.calls).to be_empty
  end
end

RSpec.shared_examples 'an inherited all' do |options|
  let(:rows) { JSON.parse(JSON.generate(options[:rows])) }
  let(:object) { described_class.new(FakeClient.new).method_name }
  let(:client) { FakeClient.new([{ method: "#{object}.get", params: {}, result: rows }]) }
  let(:resource) { described_class.new(client) }

  it 'asks for extend and nothing else' do
    resource.all
    expect(client.sent("#{object}.get")).to eq([{ 'output' => 'extend' }])
  end

  it 'maps the identify value to the id as an Integer' do
    expect(resource.all).to eq(rows.to_h { |row| [row[options[:identify]], row[options[:key]].to_i] })
  end
end

RSpec.shared_examples 'the inherited reads' do |options|
  let(:identify) { options[:identify] }
  let(:key) { options[:key] }
  let(:rows) { JSON.parse(JSON.generate(options[:rows])) }
  let(:object) { described_class.new(FakeClient.new).method_name }

  def client_answering(result)
    FakeClient.new([{ method: "#{object}.get", params: {}, result: result }])
  end

  unless Array(options[:except]).include?(:get_full_data)
    it 'get_full_data filters on identify and asks for extend' do
      client = client_answering(rows)
      expect(described_class.new(client).get_full_data(identify.to_sym => options[:value])).to eq(rows)
      expect(client.sent("#{object}.get").first).to eq('filter' => { identify => options[:value] }, 'output' => 'extend')
    end

    it 'get_full_data drops a nil filter instead of sending null' do
      client = client_answering(rows)
      described_class.new(client).get_full_data({})
      expect(client.sent("#{object}.get").first).to eq('output' => 'extend')
    end
  end

  unless Array(options[:except]).include?(:get_raw)
    it 'get_raw passes its parameters through untouched' do
      client = client_answering(rows)
      params = { output: ['name'], "#{key}s".to_sym => [options[:id]] }
      described_class.new(client).get_raw(params)
      expect(client.sent("#{object}.get").first).to eq(JSON.parse(JSON.generate(params)))
    end
  end

  unless Array(options[:except]).include?(:dump_by_id)
    it 'dump_by_id filters on the key and asks for extend' do
      client = client_answering(rows)
      described_class.new(client).dump_by_id(key.to_sym => options[:id])
      expect(client.sent("#{object}.get").first).to eq('filter' => { key => options[:id] }, 'output' => 'extend')
    end
  end
end
