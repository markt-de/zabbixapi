# Contract: ZabbixApi::Usermacros
#   evidence: spec/fixtures/usermacros/crud.json, spec/fixtures/usermacros/global.json;
#             https://www.zabbix.com/documentation/7.0/en/manual/api/reference/usermacro
#   classes:  hooks, with key overridden to hostmacroid | create and create_global send the bare
#             object the API takes, not Basic's Array, and read their own result key | the private
#             request returns nil when that key is absent | get_id and get_id_global filter on the
#             whole payload and send no output, the global pair adding the globalmacro flag | a nil
#             scope is dropped from the filter | get_full_data forwards every key, so a hostid
#             narrows it, and an empty payload drops the filter entirely | dump_by_id, get_raw and
#             all stay Basic's | all collapses one name on two hosts, and all_global is its global
#             twin, mapping each macro to an Integer globalmacroid | a secret macro's row carries no
#             value | update and update_global are issued unconditionally, read no dump, take no
#             force and refuse a payload without their own id | the four host-macro upsert branches
#             scope by hostid and strip it from the update | the four global upsert branches drop a
#             hostid outright | delete and delete_global send the bare id in an Array and return an
#             Integer | key normalisation, thirteen entry points | the server's refusals reach
#             error_message
#   not here: the vault type and the value formats behind it, server validation that the acceptance
#             spec measures; the documented get parameters, server behaviour the acceptance spec
#             measures for one select and one sortfield; template macros and what linking does, a
#             Zabbix fact about inheritance that the acceptance spec measures; bulk arrays, which
#             Usermacros#create, #delete, #create_global and #delete_global send as one call through
#             the private request, not through Basic, a path no spec runs on an Array
require 'spec_helper'

RSpec.describe ZabbixApi::Usermacros do
  crud = Fixtures.exchanges('usermacros/crud')
  global = Fixtures.exchanges('usermacros/global')

  row = Fixtures.exchange('usermacros/crud', 'usermacro.get')['result'].first
  pair = Fixtures.exchange('usermacros/crud', 'usermacro.get', 2)['result']
  secret_row = Fixtures.exchange('usermacros/crud', 'usermacro.get', 5)['result'].first
  id = row['hostmacroid'].to_i
  hostid = row['hostid'].to_i
  macro = row['macro']

  global_row = Fixtures.exchange('usermacros/global', 'usermacro.get')['result'].first
  global_id = global_row['globalmacroid'].to_i
  global_macro = global_row['macro']

  # Names of this spec's own scheme, for lookups that are meant to find nothing.
  absent = '{$ZBXAPI_SPEC_USERMACROS_ABSENT}'

  let(:client) { FakeClient.new(crud) }
  let(:usermacros) { described_class.new(client) }

  it_behaves_like 'a Basic resource', method_name: 'usermacro', identify: 'macro', key: 'hostmacroid', keys: 'hostmacroids', default_options: {}

  # Inherited unchanged: all, get_raw and dump_by_id. create, delete, update, get_id,
  # get_full_data and both upserts are overridden and get their own examples below.
  it_behaves_like 'an inherited all', identify: 'macro', key: 'hostmacroid', rows: pair
  it_behaves_like 'the inherited reads', identify: 'macro', key: 'hostmacroid', value: macro, id: id, rows: [row], except: [:get_full_data]
  it_behaves_like 'a lookup that refuses to run blind', method: :dump_by_id, field: 'hostmacroid'
  it_behaves_like 'a lookup that refuses to run blind', method: :get_id, field: 'macro'
  it_behaves_like 'a lookup that refuses to run blind', method: :get_id_global, field: 'macro'
  it_behaves_like 'the aliases', exchanges: crud, payload: { macro: macro }, id: id

  # The host-macro pair of upserts: the lookup carries the hostid, the update must not, the create
  # must. The group's id assertion also pins that the id is merged as the Integer get_id returned,
  # where Basic#create_or_update merges it as a String.
  it_behaves_like 'a host-scoped upsert',
                  identify: 'macro',
                  key: 'hostmacroid',
                  hostid: hostid,
                  payload: { macro: macro, value: 'via-upsert', hostid: hostid },
                  found: [row],
                  update_result: { hostmacroids: [id.to_s] },
                  create_result: { hostmacroids: [id.to_s] },
                  strip_on_create: false

  # One instance per entry point that reads a caller's hash, all, all_global and get_raw aside: the
  # twelve this class defines and the inherited dump_by_id. Three mechanisms are behind the
  # thirteen: the upserts, get_id and get_id_global take a symbol-keyed copy through symbolize_keys,
  # dump_by_id goes through require_id!, and the reads and writes that hand their payload straight
  # to the request normalise nothing because they need nothing - a string key becomes the same JSON
  # property. delete and delete_global are left out: they take an id, not a hash.
  it_behaves_like 'a key-normalising entry point', method: :create, payload: { hostid: hostid, macro: macro, value: 'v1' }, exchanges: crud
  it_behaves_like 'a key-normalising entry point', method: :update, payload: { hostmacroid: id, value: 'v1-updated' }, exchanges: crud
  it_behaves_like 'a key-normalising entry point', method: :get_id, payload: { macro: macro, hostid: hostid }, exchanges: crud
  it_behaves_like 'a key-normalising entry point', method: :get_full_data, payload: { macro: macro }, exchanges: crud
  it_behaves_like 'a key-normalising entry point', method: :dump_by_id, payload: { hostmacroid: id }, exchanges: crud
  it_behaves_like 'a key-normalising entry point', method: :get_or_create, payload: { hostid: hostid, macro: macro, value: 'ignored' }, exchanges: crud
  it_behaves_like 'a key-normalising entry point', method: :create_or_update, payload: { hostid: hostid, macro: macro, value: 'via-upsert' }, exchanges: crud
  it_behaves_like 'a key-normalising entry point', method: :create_global, payload: { macro: global_macro, value: 'g1' }, exchanges: global
  it_behaves_like 'a key-normalising entry point', method: :update_global, payload: { globalmacroid: global_id, value: 'g1-updated' }, exchanges: global
  it_behaves_like 'a key-normalising entry point', method: :get_id_global, payload: { macro: global_macro }, exchanges: global
  it_behaves_like 'a key-normalising entry point', method: :get_full_data_global, payload: { macro: global_macro }, exchanges: global
  it_behaves_like 'a key-normalising entry point', method: :get_or_create_global, payload: { macro: global_macro, value: 'ignored', hostid: hostid }, exchanges: global
  it_behaves_like 'a key-normalising entry point', method: :create_or_update_global, payload: { macro: global_macro, value: 'g-via-upsert', hostid: hostid }, exchanges: global

  describe '#create' do
    it 'sends the payload as the bare object usermacro.create takes, adding nothing, and returns the new id as an Integer' do
      created = Fixtures.exchange('usermacros/crud', 'usermacro.create')
      fake = FakeClient.new([created])

      expect(described_class.new(fake).create(hostid: hostid, macro: macro, value: 'v1')).to eq(created['result']['hostmacroids'].first.to_i)
      expect(fake.sent('usermacro.create')).to eq([{ 'hostid' => hostid, 'macro' => macro, 'value' => 'v1' }])
    end

    it 'returns nil when the answer carries no id under hostmacroids, whether the key is absent or empty' do
      [{ 'globalmacroids' => ['1'] }, { 'hostmacroids' => [] }].each do |result|
        fake = FakeClient.new([{ method: 'usermacro.create', result: result }])

        expect(described_class.new(fake).create(hostid: hostid, macro: macro, value: 'v1')).to be_nil
      end
    end
  end

  describe '#create_global' do
    it 'sends usermacro.createglobal as a bare object and reads the id out of globalmacroids' do
      created = Fixtures.exchange('usermacros/global', 'usermacro.createglobal')
      fake = FakeClient.new([created])

      expect(described_class.new(fake).create_global(macro: global_macro, value: 'g1')).to eq(created['result']['globalmacroids'].first.to_i)
      expect(fake.sent('usermacro.createglobal')).to eq([{ 'macro' => global_macro, 'value' => 'g1' }])
    end
  end

  describe '#get_id' do
    it 'filters on the whole payload and asks for no particular output' do
      expect(usermacros.get_id(macro: macro, hostid: hostid)).to eq(id)
      expect(client.sent('usermacro.get')).to eq([{ 'filter' => { 'macro' => macro, 'hostid' => hostid } }])
    end

    it 'drops a nil hostid from the filter instead of sending null' do
      usermacros.get_id(macro: macro, hostid: nil)

      expect(client.sent('usermacro.get').last).to eq('filter' => { 'macro' => macro })
    end

    it 'returns nil when no macro of that name sits on that host' do
      fake = FakeClient.new([Fixtures.exchange('usermacros/crud', 'usermacro.get', 1)])

      expect(described_class.new(fake).get_id(macro: absent, hostid: hostid)).to be_nil
    end
  end

  describe '#get_id_global' do
    it 'adds the globalmacro flag and reads the id out of globalmacroid' do
      fake = FakeClient.new(global)

      expect(described_class.new(fake).get_id_global(macro: global_macro)).to eq(global_id)
      expect(fake.sent('usermacro.get')).to eq([{ 'globalmacro' => true, 'filter' => { 'macro' => global_macro } }])
    end

    it 'keeps a stray hostid in the filter and returns the id the answer carries' do
      exchange = Fixtures.exchange('usermacros/global', 'usermacro.get', 2)
      fake = FakeClient.new([exchange])

      expect(described_class.new(fake).get_id_global(macro: macro, hostid: 999999)).to eq(exchange['result'].first['globalmacroid'].to_i)
      expect(fake.sent('usermacro.get')).to eq([{ 'globalmacro' => true, 'filter' => { 'macro' => macro, 'hostid' => 999999 } }])
    end

    it 'returns nil when no global macro carries that name' do
      fake = FakeClient.new([Fixtures.exchange('usermacros/global', 'usermacro.get', 1)])

      expect(described_class.new(fake).get_id_global(macro: absent)).to be_nil
    end
  end

  describe '#get_full_data' do
    it 'filters on the whole payload, asks for no particular output and returns the rows untouched' do
      exchange = Fixtures.exchange('usermacros/crud', 'usermacro.get', 2)
      fake = FakeClient.new([exchange])

      expect(described_class.new(fake).get_full_data(macro: macro)).to eq(exchange['result'])
      expect(fake.sent('usermacro.get')).to eq([{ 'filter' => { 'macro' => macro } }])
    end

    it 'forwards a hostid into the filter, and the answer holds the macro of that host alone' do
      exchange = Fixtures.exchange('usermacros/crud', 'usermacro.get', 3)
      fake = FakeClient.new([exchange])

      expect(described_class.new(fake).get_full_data(macro: macro, hostid: hostid).map { |found| found['hostid'].to_i }).to eq([hostid])
      expect(fake.sent('usermacro.get')).to eq([{ 'filter' => { 'macro' => macro, 'hostid' => hostid } }])
    end

    it 'sends no filter at all for an empty payload' do
      fake = FakeClient.new([{ method: 'usermacro.get', result: [] }])

      expect(described_class.new(fake).get_full_data({})).to eq([])
      expect(fake.sent('usermacro.get')).to eq([{}])
    end
  end

  describe '#get_full_data_global' do
    it 'adds the globalmacro flag, and the row comes back with a globalmacroid and no hostid' do
      exchange = Fixtures.exchange('usermacros/global', 'usermacro.get', 3)
      fake = FakeClient.new([exchange])
      rows = described_class.new(fake).get_full_data_global(macro: global_macro)

      expect(fake.sent('usermacro.get')).to eq([{ 'globalmacro' => true, 'filter' => { 'macro' => global_macro } }])
      expect(rows.first).to include('globalmacroid' => global_id.to_s, 'macro' => global_macro)
      expect(rows.first).not_to have_key('hostid')
    end

    it 'sends the flag alone for an empty payload, the filter being dropped' do
      fake = FakeClient.new([{ method: 'usermacro.get', result: [] }])

      expect(described_class.new(fake).get_full_data_global({})).to eq([])
      expect(fake.sent('usermacro.get')).to eq([{ 'globalmacro' => true }])
    end
  end

  describe '#dump_by_id' do
    it 'returns the row of a secret macro with type 1 and no value' do
      exchange = Fixtures.exchange('usermacros/crud', 'usermacro.get', 5)
      fake = FakeClient.new([exchange])
      dumped = described_class.new(fake).dump_by_id(hostmacroid: secret_row['hostmacroid'].to_i).first

      expect(dumped['type']).to eq('1')
      expect(dumped).not_to have_key('value')
    end
  end

  describe '#all' do
    it 'collapses the macro two hosts carry under one name into a single entry' do
      fake = FakeClient.new([{ method: 'usermacro.get', result: pair }])
      table = described_class.new(fake).all

      expect(pair.map { |found| found['hostid'] }.uniq.size).to eq(2)
      expect(table).to eq(macro => pair.last['hostmacroid'].to_i)
    end
  end

  describe '#all_global' do
    it 'maps each global macro to an Integer globalmacroid, adding the flag and asking for extend' do
      fake = FakeClient.new([Fixtures.exchange('usermacros/global', 'usermacro.get')])

      expect(described_class.new(fake).all_global(macro: global_macro)).to eq(global_macro => global_id)
      expect(fake.sent('usermacro.get')).to eq([{ 'globalmacro' => true, 'filter' => { 'macro' => global_macro }, 'output' => 'extend' }])
    end

    it 'sends the flag and output alone for a bare call, the empty filter being dropped' do
      fake = FakeClient.new([{ method: 'usermacro.get', result: [] }])

      expect(described_class.new(fake).all_global).to eq({})
      expect(fake.sent('usermacro.get')).to eq([{ 'globalmacro' => true, 'output' => 'extend' }])
    end
  end

  describe '#update' do
    it 'sends the payload as a bare object and returns the id, without reading a dump first' do
      expect(usermacros.update(hostmacroid: id, value: 'v1-updated')).to eq(id)
      expect(client.sent('usermacro.update')).to eq([{ 'hostmacroid' => id, 'value' => 'v1-updated' }])
      expect(client.count('usermacro.get')).to eq(0)
    end

    it 'issues the request again for the same data, reading nothing first' do
      2.times { usermacros.update(hostmacroid: id, value: 'v1-updated') }

      expect(client.count('usermacro.update')).to eq(2)
      expect(client.count('usermacro.get')).to eq(0)
    end

    it 'takes no force argument, so a second one raises ArgumentError before anything is sent' do
      expect { usermacros.update({ hostmacroid: id, value: 'x' }, true) }.to raise_error(ArgumentError, /wrong number of arguments/)
      expect(client.calls).to be_empty
    end

    it 'refuses a payload without a hostmacroid and sends nothing' do
      # The guard keeps this payload off the wire, so usermacros/crud holds no exchange for it.
      expect { usermacros.update(value: 'orphan') }.to raise_error(ZabbixApi::ApiError, /hostmacroid not supplied in call to update/)
      expect(client.calls).to be_empty
    end
  end

  describe '#update_global' do
    it 'sends usermacro.updateglobal as a bare object, returns the globalmacroid and reads nothing first' do
      fake = FakeClient.new(global)

      expect(described_class.new(fake).update_global(globalmacroid: global_id, value: 'g1-updated')).to eq(global_id)
      expect(fake.sent('usermacro.updateglobal')).to eq([{ 'globalmacroid' => global_id, 'value' => 'g1-updated' }])
      expect(fake.count('usermacro.get')).to eq(0)
    end

    it 'takes no force argument, so a second one raises ArgumentError before anything is sent' do
      expect { usermacros.update_global({ globalmacroid: global_id, value: 'x' }, true) }.to raise_error(ArgumentError, /wrong number of arguments/)
      expect(client.calls).to be_empty
    end

    it 'refuses a payload without a globalmacroid and sends nothing' do
      # As for #update, usermacros/global holds no exchange for this payload.
      expect { usermacros.update_global(value: 'orphan') }.to raise_error(ZabbixApi::ApiError, /globalmacroid not supplied in call to update_global/)
      expect(client.calls).to be_empty
    end
  end

  describe '#get_or_create' do
    it 'looks up with the macro and the hostid alone, never with the rest of the payload' do
      fake = FakeClient.new([Fixtures.exchange('usermacros/crud', 'usermacro.get', 7)])

      expect(described_class.new(fake).get_or_create(hostid: hostid, macro: macro, value: 'ignored')).to eq(id)
      expect(fake.sent('usermacro.get')).to eq([{ 'filter' => { 'macro' => macro, 'hostid' => hostid } }])
    end

    it 'creates with the hostid when the lookup finds nothing' do
      created = Fixtures.exchange('usermacros/crud', 'usermacro.create', 8)
      fake = FakeClient.new([Fixtures.exchange('usermacros/crud', 'usermacro.get', 8), created])
      fresh = '{$ZBXAPI_SPEC_USERMACROS_GOC}'

      expect(described_class.new(fake).get_or_create(hostid: hostid, macro: fresh, value: 'v')).to eq(created['result']['hostmacroids'].first.to_i)
      expect(fake.sent('usermacro.create')).to eq([{ 'hostid' => hostid, 'macro' => fresh, 'value' => 'v' }])
    end
  end

  describe 'the global upserts' do
    it 'get_or_create_global drops a hostid from the lookup' do
      fake = FakeClient.new([Fixtures.exchange('usermacros/global', 'usermacro.get', 5)])

      expect(described_class.new(fake).get_or_create_global(macro: global_macro, value: 'ignored', hostid: hostid)).to eq(global_id)
      expect(fake.sent('usermacro.get')).to eq([{ 'globalmacro' => true, 'filter' => { 'macro' => global_macro } }])
      expect(fake.count('usermacro.createglobal')).to eq(0)
    end

    it 'get_or_create_global creates without the hostid it was handed when nothing matches' do
      created = Fixtures.exchange('usermacros/global', 'usermacro.createglobal', 5)
      fake = FakeClient.new([Fixtures.exchange('usermacros/global', 'usermacro.get', 6), created])
      fresh = '{$ZBXAPI_SPEC_USERMACROS_GGOC}'

      expect(described_class.new(fake).get_or_create_global(macro: fresh, value: 'gv', hostid: hostid)).to eq(created['result']['globalmacroids'].first.to_i)
      expect(fake.sent('usermacro.createglobal')).to eq([{ 'macro' => fresh, 'value' => 'gv' }])
    end

    it 'create_or_update_global updates with the globalmacroid merged in and no hostid' do
      fake = FakeClient.new([Fixtures.exchange('usermacros/global', 'usermacro.get', 7), Fixtures.exchange('usermacros/global', 'usermacro.updateglobal', 2)])

      expect(described_class.new(fake).create_or_update_global(macro: global_macro, value: 'g-via-upsert', hostid: hostid)).to eq(global_id)
      expect(fake.sent('usermacro.updateglobal')).to eq([{ 'macro' => global_macro, 'value' => 'g-via-upsert', 'globalmacroid' => global_id }])
    end

    it 'create_or_update_global creates when no global macro carries the name yet' do
      created = Fixtures.exchange('usermacros/global', 'usermacro.createglobal', 6)
      fake = FakeClient.new([Fixtures.exchange('usermacros/global', 'usermacro.get', 8), created])
      fresh = '{$ZBXAPI_SPEC_USERMACROS_GCOU}'

      expect(described_class.new(fake).create_or_update_global(macro: fresh, value: 'gv')).to eq(created['result']['globalmacroids'].first.to_i)
      expect(fake.sent('usermacro.createglobal')).to eq([{ 'macro' => fresh, 'value' => 'gv' }])
      expect(fake.count('usermacro.updateglobal')).to eq(0)
    end
  end

  describe '#delete' do
    it 'sends the bare id inside an Array and returns an Integer, whichever type it was given' do
      by_integer = Fixtures.exchange('usermacros/crud', 'usermacro.delete')
      by_string = Fixtures.exchange('usermacros/crud', 'usermacro.delete', 1)
      integer_id = by_integer['result']['hostmacroids'].first.to_i
      string_id = by_string['result']['hostmacroids'].first
      first = FakeClient.new([by_integer])
      second = FakeClient.new([by_string])

      # usermacro.delete answers with a String for either input, where hostgroup.delete echoes the
      # type it was given; the wrapper returns an Integer in both cases.
      expect([by_integer['result']['hostmacroids'].first, string_id]).to all(be_a(String))
      expect(described_class.new(first).delete(integer_id)).to eq(integer_id)
      expect(described_class.new(second).delete(string_id)).to eq(string_id.to_i)
      expect([first.sent('usermacro.delete'), second.sent('usermacro.delete')]).to eq([[[integer_id]], [[string_id]]])
    end
  end

  describe '#delete_global' do
    it 'sends usermacro.deleteglobal with the id in an Array and returns it as an Integer' do
      exchange = Fixtures.exchange('usermacros/global', 'usermacro.deleteglobal')
      fake = FakeClient.new([exchange])
      gone = exchange['result']['globalmacroids'].first.to_i

      expect(described_class.new(fake).delete_global(gone)).to eq(gone)
      expect(fake.sent('usermacro.deleteglobal')).to eq([[gone]])
    end
  end

  describe 'a request the server refuses' do
    it 'raises ApiError carrying the server reason in error_message, for a refused create, update and delete' do
      [
        [Fixtures.exchange('usermacros/crud', 'usermacro.create', 1), /already exists on/, ->(wrapper) { wrapper.create(hostid: hostid, macro: macro, value: 'again') }],
        [Fixtures.exchange('usermacros/crud', 'usermacro.create', 2), /the parameter "hostid" is missing/, ->(wrapper) { wrapper.create(macro: absent, value: 'v') }],
        [Fixtures.exchange('usermacros/crud', 'usermacro.create', 3), /incorrect syntax near "not_a_macro"/, ->(wrapper) { wrapper.create(hostid: hostid, macro: 'not_a_macro', value: 'v') }],
        [Fixtures.exchange('usermacros/crud', 'usermacro.create', 4), /unexpected parameter "automatic"/, ->(wrapper) { wrapper.create(hostid: hostid, macro: absent, value: 'v', automatic: 1) }],
        [Fixtures.exchange('usermacros/crud', 'usermacro.create', 5), /value must be one of 0, 1, 2/, ->(wrapper) { wrapper.create(hostid: hostid, macro: absent, value: 'v', type: 3) }],
        [Fixtures.exchange('usermacros/crud', 'usermacro.update', 3), /unexpected parameter "hostid"/, ->(wrapper) { wrapper.update(hostmacroid: id, hostid: hostid, value: 'moved') }],
        [Fixtures.exchange('usermacros/crud', 'usermacro.delete', 2), /No permissions to referred object or it does not exist/, ->(wrapper) { wrapper.delete(999999999) }]
      ].each do |exchange, reason, call|
        wrapper = described_class.new(FakeClient.new([exchange]))

        expect { call.call(wrapper) }.to raise_error(ZabbixApi::ApiError) { |error| expect(error.error_message).to match(reason) }
      end
    end

    it 'raises ApiError carrying the server reason in error_message, for a refused create_global, update_global and delete_global' do
      [
        [Fixtures.exchange('usermacros/global', 'usermacro.createglobal', 1), /already exists/, ->(wrapper) { wrapper.create_global(macro: global_macro, value: 'again') }],
        [Fixtures.exchange('usermacros/global', 'usermacro.createglobal', 2), /unexpected parameter "hostid"/, ->(wrapper) { wrapper.create_global(macro: absent, value: 'g', hostid: hostid) }],
        [Fixtures.exchange('usermacros/global', 'usermacro.createglobal', 3), /the parameter "value" is missing/, ->(wrapper) { wrapper.create_global(macro: absent) }],
        [Fixtures.exchange('usermacros/global', 'usermacro.updateglobal', 1), /unexpected parameter "hostid"/, ->(wrapper) { wrapper.update_global(globalmacroid: global_id, hostid: hostid, value: 'x') }],
        [Fixtures.exchange('usermacros/global', 'usermacro.deleteglobal', 1), /No permissions to referred object or it does not exist/, ->(wrapper) { wrapper.delete_global(999999999) }]
      ].each do |exchange, reason, call|
        wrapper = described_class.new(FakeClient.new([exchange]))

        expect { call.call(wrapper) }.to raise_error(ZabbixApi::ApiError) { |error| expect(error.error_message).to match(reason) }
      end
    end
  end
end
