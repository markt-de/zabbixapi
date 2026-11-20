# Contract: ZabbixApi::Basic - basic_logic.rb, the CRUD every resource class inherits
#   classes:  create wraps one object and merges the defaults under the caller, and sends an Array
#             as one bulk request | a result carrying several ids yields the first for a single call
#             and every id for a bulk one | delete sends the bare id it was given, an Array of ids
#             as one request, and returns an Integer for either echo | update dumps, compares
#             against the row whose id matches, skips, issues, forces, and refuses without an id |
#             the upsert pair branches on get_id, scopes by identify alone and merges the id in as a
#             String | get_full_data, get_raw and dump_by_id and what each sends, get_raw alone
#             passing a nil value through | all maps identify to an Integer id, collapses a repeated
#             name and merges an optional scope into the filter | get_id filters on the whole hash
#             and refuses when more than one row matches, the upsert pair with it | key
#             normalisation, six mechanisms | a server refusal reaches error_message
#   not here: the aliases and the helpers, which basic_alias_spec.rb and basic_func_spec.rb assert;
#             that a string-keyed create sends each property once, which only the generated request
#             body shows - FakeClient stores the parsed wire form, where a duplicate key has already
#             collapsed, so the merge onto one set of keys is asserted on the Hash instead
#             (basic_func_spec.rb, #merge_params); a fixture and an acceptance spec, Basic having no
#             API object of its own: every response below is scripted in the shapes a server answers
#             with, rows with every scalar a String and ids under the plural of the id field
require 'spec_helper'

module BasicLogicSpec
  # What a resource class is at its thinnest: the name of its API object and its lookup field.
  class Thing < ZabbixApi::Basic
    def method_name
      'thing'
    end

    def identify
      'name'
    end
  end

  # Thing plus this hook, which Items, Hosts, HttpTests and Drules override.
  class Defaulted < Thing
    def default_options
      { name: nil, status: 0, tags: [] }
    end
  end
end

RSpec.describe ZabbixApi::Basic do
  # Rows as a server answers them: every scalar a String.
  row = { 'thingid' => '42', 'name' => 'alpha', 'status' => '0' }
  twin = { 'thingid' => '43', 'name' => 'alpha', 'status' => '1' }
  other = { 'thingid' => '44', 'name' => 'beta', 'status' => '0' }
  id = 42
  name = 'alpha'

  read = { method: 'thing.get', params: {}, result: [row] }
  nothing = { method: 'thing.get', params: {}, result: [] }
  created = { method: 'thing.create', params: {}, result: { 'thingids' => ['42'] } }
  updated = { method: 'thing.update', params: {}, result: { 'thingids' => ['42'] } }
  deleted = { method: 'thing.delete', params: {}, result: { 'thingids' => ['42'] } }

  describe BasicLogicSpec::Thing do
    it_behaves_like 'an inherited create', payload: { name: name }, defaults: {}, exchange: created
    it_behaves_like 'an inherited delete', id: id, exchange: deleted
    it_behaves_like 'an inherited get_id', identify: 'name', key: 'thingid', value: name, rows: [row]
    it_behaves_like 'an inherited all', identify: 'name', key: 'thingid', rows: [row, other]
    it_behaves_like 'the inherited reads', identify: 'name', key: 'thingid', value: name, id: id, rows: [row]
    it_behaves_like 'an update that skips when unchanged', key: 'thingid', id: id, dump: [row], unchanged: { name: name }, changed: { name: 'alpha-renamed' }, collection: { tags: [{ tag: 'spec', value: 'x' }] }

    it_behaves_like 'a lookup that refuses to run blind', method: :dump_by_id, field: 'thingid'
    it_behaves_like 'a lookup that refuses to run blind', method: :get_id, field: 'name'

    # One instance per normalisation mechanism, one per method for the upsert pair: the plain
    # symbolize_keys of a filter-building read, the conditional one of get_id, require_field! inside
    # dump_by_id, the dump comparison of update, and the upsert pair's read of the identify value.
    # create is the sixth and needs default_options to differ from get_full_data, so it sits under
    # Defaulted below.
    it_behaves_like 'a key-normalising entry point', method: :get_full_data, payload: { name: name }, exchanges: [read]
    it_behaves_like 'a key-normalising entry point', method: :get_id, payload: { name: name }, exchanges: [read]
    it_behaves_like 'a key-normalising entry point', method: :dump_by_id, payload: { thingid: id }, exchanges: [read]
    it_behaves_like 'a key-normalising entry point', method: :update, payload: { thingid: id, name: name }, exchanges: [read, updated]
    it_behaves_like 'a key-normalising entry point', method: :create_or_update, payload: { name: name, status: 1 }, exchanges: [read, read, updated]
    it_behaves_like 'a key-normalising entry point', method: :get_or_create, payload: { name: name }, exchanges: [read]

    describe '#create' do
      it 'keeps the first id when the server answers with several' do
        client = FakeClient.new([{ method: 'thing.create', params: {}, result: { 'thingids' => %w[51 52] } }])
        expect(described_class.new(client).create(name: name)).to eq(51)
      end

      # The same server answer as above, and a different return: bulk follows the shape of the call,
      # not of the result.
      it 'sends an Array payload as one request and answers every id' do
        client = FakeClient.new([{ method: 'thing.create', params: {}, result: { 'thingids' => %w[51 52] } }])
        expect(described_class.new(client).create([{ name: name }, { name: 'beta' }])).to eq([51, 52])
        expect(client.sent('thing.create')).to eq([[{ 'name' => name }, { 'name' => 'beta' }]])
      end

      it 'raises ApiError carrying the server reason in error_message, for a refused create' do
        refusal = { method: 'thing.create', params: {}, error: { 'code' => -32602, 'message' => 'Invalid params.', 'data' => 'Invalid parameter "/1": unexpected parameter "flags".' } }
        expect { described_class.new(FakeClient.new([refusal])).create(name: name, flags: 4) }
          .to raise_error(ZabbixApi::ApiError) { |error| expect(error.error_message).to match(/unexpected parameter/) }
      end
    end

    describe '#delete' do
      # Some objects echo the id in the type they were given, others answer with a String whatever
      # they got; the wrapper returns an Integer for both.
      it 'sends the id in the type it was given and returns an Integer for either echo' do
        by_string = FakeClient.new([deleted])
        by_integer = FakeClient.new([{ method: 'thing.delete', params: {}, result: { 'thingids' => [42] } }])
        expect(described_class.new(by_string).delete('42')).to eq(id)
        expect(described_class.new(by_integer).delete(id)).to eq(id)
        expect([by_string.sent('thing.delete'), by_integer.sent('thing.delete')]).to eq([[['42']], [[42]]])
      end

      it 'sends an Array of ids as one request and answers every id' do
        client = FakeClient.new([{ method: 'thing.delete', params: {}, result: { 'thingids' => %w[42 43] } }])
        expect(described_class.new(client).delete([42, 43])).to eq([42, 43])
        expect(client.sent('thing.delete')).to eq([[42, 43]])
      end
    end

    describe '#update' do
      it 'refuses a payload that names no id, before any request' do
        client = FakeClient.new([read])
        expect { described_class.new(client).update(name: name) }.to raise_error(ZabbixApi::ApiError, /thingid not supplied in call to dump_by_id/)
        expect(client.calls).to be_empty
      end

      it 'compares against the row whose id matches, not against the last row of the dump' do
        client = FakeClient.new([{ method: 'thing.get', params: {}, result: [row, other] }])
        expect(described_class.new(client).update(thingid: id, name: name)).to eq(id)
        expect(client.count('thing.update')).to eq(0)
      end

      it 'issues the update when the dump comes back empty' do
        client = FakeClient.new([nothing, updated])
        expect(described_class.new(client).update(thingid: id, name: name)).to eq(id)
        expect(client.count('thing.update')).to eq(1)
      end
    end

    describe '#create_or_update' do
      it 'looks the name up alone, dumps the object and updates it with the id merged in as a String' do
        client = FakeClient.new([read, read, updated])
        expect(described_class.new(client).create_or_update(name: name, status: 1)).to eq(id)
        expect(client.sent('thing.get')).to eq([{ 'filter' => { 'name' => name }, 'output' => %w[thingid name] }, { 'filter' => { 'thingid' => '42' }, 'output' => 'extend' }])
        expect(client.sent('thing.update')).to eq([[{ 'name' => name, 'status' => 1, 'thingid' => '42' }]])
      end

      it 'creates the payload as it stands when no object carries that name' do
        client = FakeClient.new([nothing, { method: 'thing.create', params: {}, result: { 'thingids' => ['61'] } }])
        expect(described_class.new(client).create_or_update(name: 'gamma', status: 1)).to eq(61)
        expect(client.sent('thing.create')).to eq([[{ 'name' => 'gamma', 'status' => 1 }]])
        expect(client.count('thing.update')).to eq(0)
      end

      # The upsert pair scopes by identify alone, so it is where the ambiguity refusal reaches a
      # write path, as on Scripts, whose name is unique only per menu path.
      it 'refuses rather than updating an arbitrary one of two objects sharing the name' do
        client = FakeClient.new([{ method: 'thing.get', params: {}, result: [row, twin] }])
        expect { described_class.new(client).create_or_update(name: name, status: 1) }.to raise_error(ZabbixApi::ApiError, /get_id matched 2 thing objects, not one \(thingid 42, 43\)/)
        expect(client.count('thing.update')).to eq(0)
      end
    end

    describe '#get_or_create' do
      it 'returns the id the lookup found and creates nothing' do
        client = FakeClient.new([read])
        expect(described_class.new(client).get_or_create(name: name, status: 1)).to eq(id)
        expect(client.sent('thing.get')).to eq([{ 'filter' => { 'name' => name }, 'output' => %w[thingid name] }])
        expect(client.count('thing.create')).to eq(0)
      end

      it 'creates the whole payload when the lookup finds nothing' do
        client = FakeClient.new([nothing, { method: 'thing.create', params: {}, result: { 'thingids' => ['62'] } }])
        expect(described_class.new(client).get_or_create(name: 'gamma', status: 1)).to eq(62)
        expect(client.sent('thing.create')).to eq([[{ 'name' => 'gamma', 'status' => 1 }]])
      end

      it 'refuses rather than returning an arbitrary one of two objects sharing the name' do
        client = FakeClient.new([{ method: 'thing.get', params: {}, result: [row, twin] }])
        expect { described_class.new(client).get_or_create(name: name) }.to raise_error(ZabbixApi::ApiError, /matched 2 thing objects/)
        expect(client.count('thing.create')).to eq(0)
      end
    end

    describe '#get_id' do
      it 'refuses when several objects carry the identify value, naming every id it found' do
        client = FakeClient.new([{ method: 'thing.get', params: {}, result: [row, twin] }])
        expect { described_class.new(client).get_id(name: name) }.to raise_error(ZabbixApi::ApiError, /\Aget_id matched 2 thing objects, not one \(thingid 42, 43\): narrow the lookup\z/)
      end

      it 'returns the id when a lookup carrying a further field is answered with one row' do
        client = FakeClient.new([{ method: 'thing.get', params: {}, result: [twin] }])
        expect(described_class.new(client).get_id(name: name, status: 1)).to eq(43)
      end

      it 'ignores a row whose identify value only resembles the one asked for' do
        client = FakeClient.new([{ method: 'thing.get', params: {}, result: [{ 'thingid' => '45', 'name' => 'alphabet' }] }])
        expect(described_class.new(client).get_id(name: name)).to be_nil
      end

      it 'filters on every field it was given and drops the ones carrying no value' do
        client = FakeClient.new([read])
        described_class.new(client).get_id(name: name, status: 0, hostid: nil)
        expect(client.sent('thing.get')).to eq([{ 'filter' => { 'name' => name, 'status' => 0 }, 'output' => %w[thingid name] }])
      end
    end

    describe '#get_raw' do
      it 'passes a nil value through, where get_full_data drops it' do
        raw = FakeClient.new([read])
        built = FakeClient.new([read])
        described_class.new(raw).get_raw(filter: { name: nil })
        described_class.new(built).get_full_data({})
        expect(raw.sent('thing.get')).to eq([{ 'filter' => { 'name' => nil } }])
        expect(built.sent('thing.get')).to eq([{ 'output' => 'extend' }])
      end
    end

    describe '#dump_by_id' do
      it 'returns the rows as an Array and filters on the id it was given, unconverted' do
        client = FakeClient.new([read])
        expect(described_class.new(client).dump_by_id(thingid: '42')).to eq([row])
        expect(client.sent('thing.get')).to eq([{ 'filter' => { 'thingid' => '42' }, 'output' => 'extend' }])
      end
    end

    describe '#all' do
      it 'collapses a name two objects share, the last row winning' do
        client = FakeClient.new([{ method: 'thing.get', params: {}, result: [row, twin, other] }])
        expect(described_class.new(client).all).to eq('alpha' => 43, 'beta' => 44)
      end

      it 'maps the name to the same Integer id get_id returns' do
        table = FakeClient.new([read])
        lookup = FakeClient.new([read])
        expect(described_class.new(table).all[name]).to eq(id)
        expect(described_class.new(lookup).get_id(name: name)).to eq(id)
      end

      # The scope is what keeps a per-owner name from collapsing: it narrows the request instead
      # of losing rows afterwards.
      it 'merges a scope into the filter' do
        client = FakeClient.new([{ method: 'thing.get', params: {}, result: [twin] }])
        expect(described_class.new(client).all(hostid: 12)).to eq('alpha' => 43)
        expect(client.sent('thing.get')).to eq([{ 'filter' => { 'hostid' => 12 }, 'output' => 'extend' }])
      end

      it 'takes the scope in either key style and drops a property it was given no value for' do
        symbol = FakeClient.new([read])
        string = FakeClient.new([read])
        described_class.new(symbol).all(hostid: 12, name: nil)
        described_class.new(string).all('hostid' => 12)
        expect(symbol.sent('thing.get')).to eq([{ 'filter' => { 'hostid' => 12 }, 'output' => 'extend' }])
        expect(string.sent('thing.get')).to eq([{ 'filter' => { 'hostid' => 12 }, 'output' => 'extend' }])
      end
    end
  end

  describe BasicLogicSpec::Defaulted do
    it_behaves_like 'an inherited create', payload: { name: name, status: 1 }, defaults: { name: nil, status: 0, tags: [] }, exchange: created
    it_behaves_like 'a key-normalising entry point', method: :create, payload: { name: name, status: 1 }, exchanges: [created]

    describe '#create' do
      it 'lets a string-keyed payload override the defaults and still sends the defaults it did not name' do
        client = FakeClient.new([created])
        described_class.new(client).create('name' => name, 'status' => 1)
        expect(client.sent('thing.create')).to eq([[{ 'name' => name, 'status' => 1, 'tags' => [] }]])
      end
    end

    describe '#get_or_create' do
      it 'creates through the defaults when the lookup finds nothing' do
        client = FakeClient.new([nothing, created])
        expect(described_class.new(client).get_or_create(name: name)).to eq(id)
        expect(client.sent('thing.create')).to eq([[{ 'name' => name, 'status' => 0, 'tags' => [] }]])
      end
    end
  end
end
