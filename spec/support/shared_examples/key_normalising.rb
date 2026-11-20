# Symbol and string keys must produce the same traffic and the same return value, a deep-frozen
# payload must be accepted, and the caller's hash must come back untouched.
RSpec.shared_examples 'a key-normalising entry point' do |options|
  let(:entry_point) { options[:method] }
  let(:payload) { options[:payload] }
  let(:exchanges) { options[:exchanges] }
  let(:extra_args) { options.fetch(:args, []) }

  def stringify(value)
    case value
    when Hash then value.each_with_object({}) { |(key, item), result| result[key.to_s] = stringify(item) }
    when Array then value.map { |item| stringify(item) }
    else value
    end
  end

  def deep_dup(value)
    case value
    when Hash then value.transform_values { |item| deep_dup(item) }
    when Array then value.map { |item| deep_dup(item) }
    when String then value.dup
    else value
    end
  end

  def deep_freeze(value)
    case value
    when Hash then value.each_value { |item| deep_freeze(item) }
    when Array then value.each { |item| deep_freeze(item) }
    end
    value.freeze
  end

  def call_with(client, data)
    described_class.new(client).public_send(entry_point, data, *extra_args)
  end

  it 'sends the same requests and returns the same value for symbol and string keys' do
    symbols = FakeClient.new(exchanges)
    strings = FakeClient.new(exchanges)
    expect(call_with(strings, stringify(payload))).to eq(call_with(symbols, payload))
    expect(strings.calls).to eq(symbols.calls)
  end

  it 'accepts a deep-frozen payload' do
    expect { call_with(FakeClient.new(exchanges), deep_freeze(deep_dup(payload))) }.not_to raise_error
  end

  it "leaves the caller's hash untouched" do
    original = deep_dup(payload)
    call_with(FakeClient.new(exchanges), payload)
    expect(payload).to eq(original)
  end
end
