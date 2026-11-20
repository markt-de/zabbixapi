# Events and Problems: the five CRUD methods and the two aliases raise locally and send nothing.
RSpec.shared_examples 'a read-only wrapper' do |options|
  let(:client) { FakeClient.new }
  let(:resource) { described_class.new(client) }

  { create: [{}], delete: [1], update: [{}], create_or_update: [{}], get_or_create: [{}], add: [{}], destroy: [1] }.each do |method, args|
    it "refuses #{method} locally and sends nothing" do
      expect { resource.public_send(method, *args) }.to raise_error(ZabbixApi::ApiError, options[:message])
      expect(client.calls).to be_empty
    end
  end
end
