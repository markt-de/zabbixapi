# Items, HttpTests, ValueMaps, Usermacros, Graphs and Triggers look an object up by its identify
# value and hostid, since that value can repeat across hosts, and must not let the hostid reach the
# update; the create keeps it unless strip_on_create is true.
RSpec.shared_examples 'a host-scoped upsert' do |options|
  let(:identify) { options[:identify] }
  let(:key) { options[:key] }
  let(:payload) { options[:payload] }
  let(:object) { described_class.new(FakeClient.new).method_name }
  let(:found) { JSON.parse(JSON.generate(options[:found])) }
  let(:found_id) { found.first[key].to_i }
  # The dump Basic#update compares against before deciding to skip. Empty by default, which never
  # satisfies skip_update?, so the update is always issued; a dump equal to the payload would make
  # the request vanish and the assertions below fail on nil.
  let(:dump_rows) { JSON.parse(JSON.generate(options.fetch(:dump, []))) }
  let(:update_exchange) { { method: "#{object}.update", params: {}, result: options[:update_result] } }

  def lookup(rows)
    { method: "#{object}.get", params: {}, result: rows }
  end

  # Basic wraps a write in an Array; Usermacros#request sends the bare object.
  def first_object(params)
    params.is_a?(Array) ? params.first : params
  end

  # The update branch issues two <obj>.get calls wherever the class routes through Basic#update:
  # the get_id lookup, then dump_by_id. Usermacros#update never reads first, so its second
  # exchange is simply never replayed and its traffic is unchanged.
  def updating
    FakeClient.new([lookup(found), lookup(dump_rows), update_exchange])
  end

  it 'looks the object up by its identify value and hostid' do
    client = updating
    described_class.new(client).create_or_update(payload)
    expect(client.sent("#{object}.get").first['filter']).to include(identify => payload[identify.to_sym], 'hostid' => options[:hostid])
  end

  it 'updates with the id and without the hostid when the object exists' do
    client = updating
    expect(described_class.new(client).create_or_update(payload)).to eq(found_id)
    sent = first_object(client.sent("#{object}.update").first)
    expect(sent).not_to have_key('hostid')
    expect(sent[key]).to eq(found_id)
  end

  it "creates #{options[:strip_on_create] ? 'without' : 'with'} the hostid when nothing matches" do
    client = FakeClient.new([lookup([]), { method: "#{object}.create", params: {}, result: options[:create_result] }])
    described_class.new(client).create_or_update(payload)
    sent = first_object(client.sent("#{object}.create").first)
    expect(sent.key?('hostid')).to eq(!options[:strip_on_create])
  end

  it 'get_or_create returns the existing id and creates nothing' do
    client = FakeClient.new([lookup(found)])
    expect(described_class.new(client).get_or_create(payload)).to eq(found_id)
    expect(client.count("#{object}.create")).to eq(0)
  end
end
