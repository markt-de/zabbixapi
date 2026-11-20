# Contract: ZabbixApi::Mediatypes
#   evidence: spec/fixtures/mediatypes/crud.json;
#             https://www.zabbix.com/documentation/7.0/en/manual/api/reference/mediatype
#   classes:  hooks, no default_options | create wraps one object and merges nothing | the three
#             inherited reads and the request each builds | all maps the name to an Integer id |
#             get_id filters on the name alone, whatever else the payload carries, and returns nil
#             for a name nothing carries | update resolves a missing id from the name, into a copy,
#             skips the lookup when the id is there, and refuses a name that matches nothing |
#             update skips an equal payload, issues a differing one, honours force and never skips
#             message_templates | the four upsert branches, the id merged in as a String where
#             get_id hands back an Integer | the three aliases | delete sends a bare id and returns
#             an Integer | key normalisation, four entry points, four mechanisms | a refusal reaches
#             error_message, from the first request and from a later one
#   not here: `all` over the real table, whose extend response carries every media type on the
#             server, webhook scripts included; the group runs on two recorded extend rows instead
#             and the live spec asserts membership in the real one; the transport requirements, the
#             enums, the ranges and the gated properties, server validation of parameters this
#             wrapper only passes through, asserted live; the three selects and mediaids/userids,
#             get_raw passthrough with one representative kept; get_id's refusal on more than one
#             match, unreachable here because media type names are unique server-wide and proven by
#             Basic's own spec; bulk arrays, which Basic#create and #delete handle and Basic's own
#             spec covers; the status default and the plaintext passwd, server facts that are
#             pending in the live spec
require 'spec_helper'

RSpec.describe ZabbixApi::Mediatypes do
  crud = Fixtures.exchanges('mediatypes/crud')
  # The Email type as extend returns it, and the Script type the upsert branch created: two real
  # rows, which is what a mediatype.get answers with wherever the recording is not replayed whole.
  row = Fixtures.exchange('mediatypes/crud', 'mediatype.get')['result'].first
  upserted = Fixtures.exchange('mediatypes/crud', 'mediatype.get', 19)['result'].first
  id = row['mediatypeid'].to_i
  name = row['name']
  absent = 'zbxapi-spec-mediatypes-absent'
  # The transport minimum the mediatype object reference requires of an Email type; with no
  # default_options to fill anything in, create sends it as given.
  email = { type: 0, smtp_server: 'smtp.example.invalid', smtp_email: 'zbxapi-spec@example.invalid' }
  template = { eventsource: 0, recovery: 0, subject: 'S', message: 'M' }

  let(:client) { FakeClient.new(crud) }
  let(:mediatypes) { described_class.new(client) }

  it_behaves_like 'a Basic resource', method_name: 'mediatype', identify: 'name', key: 'mediatypeid', keys: 'mediatypeids', default_options: {}

  it_behaves_like 'an inherited create', payload: email.merge(name: name), defaults: {}, exchange: Fixtures.exchange('mediatypes/crud', 'mediatype.create')
  it_behaves_like 'an inherited delete', id: Fixtures.exchange('mediatypes/crud', 'mediatype.delete')['params'].first, exchange: Fixtures.exchange('mediatypes/crud', 'mediatype.delete')
  it_behaves_like 'an inherited all', identify: 'name', key: 'mediatypeid', rows: [row, upserted]
  it_behaves_like 'the inherited reads', identify: 'name', key: 'mediatypeid', value: name, id: id, rows: [row]
  # message_templates is the one related collection of this object: the mediatype.update reference
  # has it replace the stored set, and extend never returns it, so a payload naming it is never
  # skipped. parameters is the counter-example and sits inside extend, so it compares like a scalar.
  it_behaves_like 'an update that skips when unchanged', key: 'mediatypeid', id: id, dump: [row], unchanged: { name: name }, changed: { description: 'first description' }, collection: { message_templates: [template] }
  it_behaves_like 'the aliases', exchanges: crud, payload: { name: name }, id: id

  it_behaves_like 'a lookup that refuses to run blind', method: :dump_by_id, field: 'mediatypeid'
  it_behaves_like 'a lookup that refuses to run blind', method: :get_id, field: 'name'

  # One instance per normalisation mechanism: the plain symbolize_keys of a filter-building read,
  # the conditional one of the get_id override, require_field! in dump_by_id, and the override that
  # symbolises before it looks an id up and hands the copy to Basic#update. create would be a fifth
  # only for a class carrying default_options, and this one carries none.
  it_behaves_like 'a key-normalising entry point', method: :get_full_data, payload: { name: name }, exchanges: crud
  it_behaves_like 'a key-normalising entry point', method: :get_id, payload: { name: name }, exchanges: crud
  it_behaves_like 'a key-normalising entry point', method: :dump_by_id, payload: { mediatypeid: id }, exchanges: crud
  it_behaves_like 'a key-normalising entry point', method: :update, payload: { mediatypeid: id, name: name }, exchanges: crud

  describe '#get_id' do
    it 'filters on the name alone when the payload carries another key' do
      scoped = FakeClient.new([Fixtures.exchange('mediatypes/crud', 'mediatype.get', 2)])

      expect(described_class.new(scoped).get_id(name: name, maxattempts: 99)).to eq(id)
      expect(scoped.sent('mediatype.get')).to eq([{ 'filter' => { 'name' => name }, 'output' => %w[mediatypeid name] }])
    end

    it 'returns nil when no media type carries the name' do
      missing = FakeClient.new([Fixtures.exchange('mediatypes/crud', 'mediatype.get', 3)])

      expect(described_class.new(missing).get_id(name: absent)).to be_nil
    end
  end

  describe '#update' do
    it 'resolves the missing id from the name and writes it into the payload it sends' do
      fake = FakeClient.new([Fixtures.exchange('mediatypes/crud', 'mediatype.get', 11), Fixtures.exchange('mediatypes/crud', 'mediatype.get', 12), Fixtures.exchange('mediatypes/crud', 'mediatype.update', 2)])

      expect(described_class.new(fake).update(name: name, description: 'second description')).to eq(id)
      expect(fake.sent('mediatype.get')).to eq([{ 'filter' => { 'name' => name }, 'output' => %w[mediatypeid name] },
                                                { 'filter' => { 'mediatypeid' => id }, 'output' => 'extend' }])
      expect(fake.sent('mediatype.update')).to eq([[{ 'name' => name, 'description' => 'second description', 'mediatypeid' => id }]])
    end

    it "leaves no resolved id behind in the caller's hash" do
      payload = { name: name, description: 'second description' }
      fake = FakeClient.new([Fixtures.exchange('mediatypes/crud', 'mediatype.get', 11), Fixtures.exchange('mediatypes/crud', 'mediatype.get', 12), Fixtures.exchange('mediatypes/crud', 'mediatype.update', 2)])

      described_class.new(fake).update(payload)
      expect(payload).to eq(name: name, description: 'second description')
    end

    it 'looks no name up when the payload already carries the id, and dumps that id instead' do
      fake = FakeClient.new([Fixtures.exchange('mediatypes/crud', 'mediatype.get', 8), Fixtures.exchange('mediatypes/crud', 'mediatype.update')])

      expect(described_class.new(fake).update(mediatypeid: id, description: 'first description')).to eq(id)
      expect(fake.sent('mediatype.get')).to eq([{ 'filter' => { 'mediatypeid' => id }, 'output' => 'extend' }])
    end

    it 'raises after the lookup and before any update when no media type carries the name, naming the name' do
      fake = FakeClient.new([Fixtures.exchange('mediatypes/crud', 'mediatype.get', 13)])

      expect { described_class.new(fake).update(name: absent, description: 'third description') }
        .to raise_error(ZabbixApi::ApiError, /\Ano mediatype found with name "#{absent}"\z/)
      expect(fake.count('mediatype.get')).to eq(1)
      expect(fake.count('mediatype.update')).to eq(0)
    end
  end

  describe '#create_or_update' do
    it 'looks the name up, dumps the object and updates it with the id merged in as a String' do
      found = Fixtures.exchange('mediatypes/crud', 'mediatype.get', 18)
      target = found['result'].first
      fake = FakeClient.new([found, Fixtures.exchange('mediatypes/crud', 'mediatype.get', 19), Fixtures.exchange('mediatypes/crud', 'mediatype.update', 5)])

      expect(described_class.new(fake).create_or_update(name: target['name'], description: 'per upsert')).to eq(target['mediatypeid'].to_i)
      expect(fake.sent('mediatype.get')).to eq([{ 'filter' => { 'name' => target['name'] }, 'output' => %w[mediatypeid name] },
                                                { 'filter' => { 'mediatypeid' => target['mediatypeid'] }, 'output' => 'extend' }])
      expect(fake.sent('mediatype.update')).to eq([[{ 'name' => target['name'], 'description' => 'per upsert', 'mediatypeid' => target['mediatypeid'] }]])
    end

    it 'creates the payload untouched when the name exists nowhere, and issues no update' do
      created = Fixtures.exchange('mediatypes/crud', 'mediatype.create', 4)
      fake = FakeClient.new([Fixtures.exchange('mediatypes/crud', 'mediatype.get', 20), created])
      unseen = 'zbxapi-spec-mediatypes-cou'

      expect(described_class.new(fake).create_or_update(email.merge(name: unseen))).to eq(created['result']['mediatypeids'].first.to_i)
      expect(fake.sent('mediatype.create')).to eq([[JSON.parse(JSON.generate(email.merge(name: unseen)))]])
      expect(fake.count('mediatype.update')).to eq(0)
    end
  end

  describe '#get_or_create' do
    it 'returns the id the lookup found and creates nothing' do
      found = Fixtures.exchange('mediatypes/crud', 'mediatype.get', 16)
      fake = FakeClient.new([found])

      expect(described_class.new(fake).get_or_create(email.merge(name: name))).to eq(found['result'].first['mediatypeid'].to_i)
      expect(fake.count('mediatype.create')).to eq(0)
    end

    it 'creates the whole payload when the lookup finds nothing, filtering on the name alone' do
      created = Fixtures.exchange('mediatypes/crud', 'mediatype.create', 3)
      fake = FakeClient.new([Fixtures.exchange('mediatypes/crud', 'mediatype.get', 17), created])
      script = { type: 1, exec_path: 'notify.sh', name: 'zbxapi-spec-mediatypes-goc' }

      expect(described_class.new(fake).get_or_create(script)).to eq(created['result']['mediatypeids'].first.to_i)
      expect(fake.sent('mediatype.get')).to eq([{ 'filter' => { 'name' => script[:name] }, 'output' => %w[mediatypeid name] }])
      expect(fake.sent('mediatype.create')).to eq([[JSON.parse(JSON.generate(script))]])
    end
  end

  describe 'a refusal the server sent back' do
    it "reaches the caller as an ApiError whose error_message joins the server's message and data" do
      fake = FakeClient.new([Fixtures.exchange('mediatypes/crud', 'mediatype.create', 1)])

      expect { described_class.new(fake).create(email.merge(name: name)) }
        .to raise_error(ZabbixApi::ApiError) { |error| expect(error.error_message).to match(/\AInvalid params\.: Media type .* already exists\.\z/) }
    end

    it 'reaches the caller from the second request too, the dump before it having succeeded' do
      fake = FakeClient.new([Fixtures.exchange('mediatypes/crud', 'mediatype.get', 15), Fixtures.exchange('mediatypes/crud', 'mediatype.update', 4)])

      expect { described_class.new(fake).update(mediatypeid: id, maxattempts: 101) }
        .to raise_error(ZabbixApi::ApiError) { |error| expect(error.error_message).to match(/value must be one of 1-100/) }
      expect(fake.count('mediatype.get')).to eq(1)
    end
  end
end
