# get, add and destroy are Basic's aliases for get_full_data, create and delete.
RSpec.shared_examples 'the aliases' do |options|
  let(:exchanges) { options[:exchanges] }
  let(:payload) { options[:payload] }
  let(:id) { options[:id] }

  def calls_of(method, *args)
    client = FakeClient.new(exchanges)
    described_class.new(client).public_send(method, *args)
    client.calls
  end

  it 'get sends the same requests as get_full_data' do
    expect(calls_of(:get, payload)).to eq(calls_of(:get_full_data, payload))
  end

  it 'add sends the same requests as create' do
    expect(calls_of(:add, payload)).to eq(calls_of(:create, payload))
  end

  it 'destroy sends the same requests as delete' do
    expect(calls_of(:destroy, id)).to eq(calls_of(:delete, id))
  end
end
