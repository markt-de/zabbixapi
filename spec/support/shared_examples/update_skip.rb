# Basic#update dumps the object, compares, and skips the request when nothing differs - only for
# fields the dump contains, and never under force.
RSpec.shared_examples 'an update that skips when unchanged' do |options|
  let(:key) { options[:key] }
  let(:id) { options[:id] }
  let(:object) { described_class.new(FakeClient.new).method_name }
  let(:dump) { options[:dump] }
  let(:unchanged) { options[:unchanged] }
  let(:changed) { options[:changed] }
  let(:update_result) { options.fetch(:update_result) { { "#{key}s" => [id.to_s] } } }

  def client_with_dump(*extra)
    FakeClient.new([{ method: "#{object}.get", params: {}, result: dump }] + extra)
  end

  def update_exchange
    { method: "#{object}.update", params: {}, result: update_result }
  end

  def wire(value)
    JSON.parse(JSON.generate(value))
  end

  it 'skips the request when every given field already matches the dump' do
    client = client_with_dump
    expect(described_class.new(client).update({ key.to_sym => id }.merge(unchanged))).to eq(id)
    expect(client.count("#{object}.update")).to eq(0)
  end

  it 'issues exactly one update, the id plus the given fields, when a field differs' do
    client = client_with_dump(update_exchange)
    expect(described_class.new(client).update({ key.to_sym => id }.merge(changed))).to eq(id)
    expect(client.sent("#{object}.update")).to eq([[wire({ key => id }.merge(changed))]])
  end

  it 'issues the update under force although nothing differs' do
    client = client_with_dump(update_exchange)
    described_class.new(client).update({ key.to_sym => id }.merge(unchanged), true)
    expect(client.count("#{object}.update")).to eq(1)
  end

  if options[:collection]
    it 'issues the update for a related collection the dump cannot show' do
      client = client_with_dump(update_exchange)
      described_class.new(client).update({ key.to_sym => id }.merge(options[:collection]))
      expect(client.count("#{object}.update")).to eq(1)
    end
  end
end
