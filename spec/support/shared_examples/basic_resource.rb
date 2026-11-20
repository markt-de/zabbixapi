# The five hooks a resource class defines or inherits from Basic.
RSpec.shared_examples 'a Basic resource' do |options|
  let(:resource) { described_class.new(FakeClient.new) }

  it "names the API object #{options[:method_name]}" do
    expect(resource.method_name).to eq(options[:method_name])
  end

  it "identifies by #{options[:identify]}" do
    expect(resource.identify).to eq(options[:identify])
  end

  it "keys by #{options[:key]}, plural #{options[:keys]}" do
    expect([resource.key, resource.keys]).to eq([options[:key], options[:keys]])
  end

  it 'carries exactly the given default_options' do
    expect(resource.default_options).to eq(options[:default_options])
  end
end
