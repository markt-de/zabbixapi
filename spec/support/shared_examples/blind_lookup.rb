# A lookup given nothing to select on raises before any request: an empty hash, and the field under
# a symbol or a string key with nil.
RSpec.shared_examples 'a lookup that refuses to run blind' do |options|
  let(:client) { FakeClient.new }
  let(:resource) { described_class.new(client) }
  let(:field) { options[:field] }
  let(:pattern) { /#{field} not supplied/ }

  it 'raises on an empty hash and sends nothing' do
    expect { resource.public_send(options[:method], {}) }.to raise_error(ZabbixApi::ApiError, pattern)
    expect(client.calls).to be_empty
  end

  it 'raises on a nil value under a symbol key and under a string key' do
    expect { resource.public_send(options[:method], field.to_sym => nil) }.to raise_error(ZabbixApi::ApiError, pattern)
    expect { resource.public_send(options[:method], field.to_s => nil) }.to raise_error(ZabbixApi::ApiError, pattern)
    expect(client.calls).to be_empty
  end

  Array(options[:also]).each do |alias_name|
    it "raises on a nil #{alias_name} too" do
      expect { resource.public_send(options[:method], alias_name.to_sym => nil) }.to raise_error(ZabbixApi::ApiError, pattern)
      expect(client.calls).to be_empty
    end
  end
end
