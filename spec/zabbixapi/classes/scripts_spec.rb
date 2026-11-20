# Contract: ZabbixApi::Scripts
#   evidence: spec/fixtures/scripts/crud.json, spec/fixtures/scripts/execute.json,
#             spec/fixtures/scripts/byevents.json;
#             https://www.zabbix.com/documentation/7.0/en/manual/api/reference/script
#   classes:  hooks, and the three methods the class adds | create wraps one object and merges no
#             defaults | the four reads and what each sends | one name two scripts carry: all keeps
#             the last row, get_id refuses | update skips equal, issues differing, honours force,
#             and skips a parameters payload too because script.get extend returns them | the four
#             upsert branches, the id merged in as a String | the three aliases | delete sends a
#             bare id and returns an Integer, although script.delete answered a String | execute
#             sends only the parameters given, host branch and event branch | the two execute return
#             shapes, webhook and other | getscriptsbyhost passes object and array through to the
#             plural method and omits the foreign-group script execute would refuse |
#             getscriptsbyevents passes object and array through under its own plural spelling, and
#             lists the scopes execute refuses for an event | refusals of create, update, delete,
#             execute and both getscriptsby* methods
#   not here: the full type x scope matrix and every enum bound, which are server validation: one
#             accepted pair and one refused value are kept, and the acceptance spec holds further
#             representatives; every property gated to a type or scope and sent outside it, one
#             representative kept (menu_path outside scopes 2 and 4); that the server returns
#             password, publickey and privatekey in plaintext, which the gem passes through and a
#             recording cannot show for the password, scrubbed on write; execute_on 0, which against
#             a host no agent polls hangs until the HTTP timeout, so no recording holds it; the
#             documented get parameters, one get_raw representative kept
require 'spec_helper'

RSpec.describe ZabbixApi::Scripts do
  crud = Fixtures.exchanges('scripts/crud')
  created = Fixtures.exchange('scripts/crud', 'script.create')
  row = Fixtures.exchange('scripts/crud', 'script.get')['result'].first
  table = Fixtures.exchange('scripts/crud', 'script.get', 6)['result']
  deleted = Fixtures.exchange('scripts/crud', 'script.delete')
  id = row['scriptid'].to_i
  name = row['name']
  command = created['params'].first['command']
  duplicated = Fixtures.exchange('scripts/crud', 'script.get', 3)

  ran = Fixtures.exchange('scripts/execute', 'script.execute')
  offered = Fixtures.exchange('scripts/execute', 'script.getscriptsbyhosts')
  script_id = ran['params']['scriptid']
  host_id = ran['params']['hostid']

  by_event = Fixtures.exchange('scripts/byevents', 'script.getscriptsbyevents')
  event_id = by_event['params']['eventid']
  event_script = Fixtures.exchange('scripts/byevents', 'script.getscriptsbyevents', 2)['params']['scriptid']

  let(:client) { FakeClient.new(crud) }
  let(:scripts) { described_class.new(client) }

  it_behaves_like 'a Basic resource', method_name: 'script', identify: 'name', key: 'scriptid', keys: 'scriptids', default_options: {}

  it_behaves_like 'an inherited create', payload: { name: name, scope: 1, type: 0, command: command }, defaults: {}, exchange: created
  it_behaves_like 'an inherited delete', id: deleted['params'].first, exchange: deleted
  it_behaves_like 'an inherited get_id', identify: 'name', key: 'scriptid', value: name, rows: [row]
  it_behaves_like 'an inherited all', identify: 'name', key: 'scriptid', rows: table
  it_behaves_like 'the inherited reads', identify: 'name', key: 'scriptid', value: name, id: id, rows: [row]
  it_behaves_like 'an update that skips when unchanged', key: 'scriptid', id: id, dump: [row], unchanged: { name: name }, changed: { description: 'zbxapi-spec after' }
  it_behaves_like 'the aliases', exchanges: crud, payload: { name: name }, id: id

  it_behaves_like 'a lookup that refuses to run blind', method: :dump_by_id, field: 'scriptid'
  it_behaves_like 'a lookup that refuses to run blind', method: :get_id, field: 'name'

  # One instance per normalisation mechanism of the inherited entry points - the plain
  # symbolize_keys of a filter-building read, the conditional one in get_id, require_field! in
  # dump_by_id, the dump comparison in update - plus the three methods the class adds. create is
  # not a mechanism of its own here: without default_options it is the get_full_data case. execute
  # symbolizes like the reads; getscriptsbyhost and getscriptsbyevents normalise nothing and pass
  # the caller's hash straight to the client, so what this proves for them is that both key styles
  # survive that passthrough on the wire.
  it_behaves_like 'a key-normalising entry point', method: :get_full_data, payload: { name: name }, exchanges: crud
  it_behaves_like 'a key-normalising entry point', method: :get_id, payload: { name: name }, exchanges: crud
  it_behaves_like 'a key-normalising entry point', method: :dump_by_id, payload: { scriptid: id }, exchanges: crud
  it_behaves_like 'a key-normalising entry point', method: :update, payload: { scriptid: id, description: 'zbxapi-spec after' }, exchanges: crud
  it_behaves_like 'a key-normalising entry point', method: :execute, payload: { scriptid: script_id, hostid: host_id }, exchanges: [ran]
  it_behaves_like 'a key-normalising entry point', method: :getscriptsbyhost, payload: { hostid: host_id }, exchanges: [offered]
  it_behaves_like 'a key-normalising entry point', method: :getscriptsbyevents, payload: { eventid: event_id }, exchanges: [by_event]

  describe 'the class surface' do
    it 'adds execute, getscriptsbyhost and getscriptsbyevents and specialises nothing else' do
      expect((described_class.public_instance_methods(false) - ZabbixApi::Basic.public_instance_methods).sort).to eq([:execute, :getscriptsbyevents, :getscriptsbyhost])
    end
  end

  describe '#update' do
    it 'raises before any request when the payload names no scriptid' do
      expect { scripts.update(description: 'zbxapi-spec after') }.to raise_error(ZabbixApi::ApiError, /scriptid not supplied in call to dump_by_id/)
      expect(client.calls).to be_empty
    end

    it 'skips the request for a parameters payload the dump already carries' do
      dump = Fixtures.exchange('scripts/crud', 'script.get', 9)
      webhook = dump['result'].first
      fake = FakeClient.new([dump])

      expect(described_class.new(fake).update(scriptid: webhook['scriptid'].to_i, parameters: [{ name: 'token', value: '{$ZBXAPI_SPEC}' }])).to eq(webhook['scriptid'].to_i)
      expect(fake.count('script.update')).to eq(0)
    end

    it 'issues the call under force and raises the refusal of a scope an action still needs' do
      refusal = Fixtures.exchange('scripts/crud', 'script.update', 3)
      payload = refusal['params'].first
      fake = FakeClient.new([Fixtures.exchange('scripts/crud', 'script.get', 18), refusal])

      expect { described_class.new(fake).update({ scriptid: payload['scriptid'], scope: payload['scope'], groupid: payload['groupid'] }, true) }
        .to raise_error(ZabbixApi::ApiError) { |error| expect(error.error_message).to match(/Cannot update script scope/) }
      expect(fake.sent('script.update')).to eq([[payload]])
    end
  end

  describe '#create_or_update' do
    it 'looks the name up, dumps the script and updates it with the id merged in as a String' do
      lookup = Fixtures.exchange('scripts/crud', 'script.get', 13)
      found = lookup['result'].first
      fake = FakeClient.new([lookup, Fixtures.exchange('scripts/crud', 'script.get', 14), Fixtures.exchange('scripts/crud', 'script.update', 2)])

      expect(described_class.new(fake).create_or_update(name: found['name'], scope: 1, type: 0, command: command, description: 'zbxapi-spec upserted')).to eq(found['scriptid'].to_i)
      expect(fake.sent('script.get')).to eq([{ 'filter' => { 'name' => found['name'] }, 'output' => %w[scriptid name] }, { 'filter' => { 'scriptid' => found['scriptid'] }, 'output' => 'extend' }])
      expect(fake.sent('script.update')).to eq([[{ 'name' => found['name'], 'scope' => 1, 'type' => 0, 'command' => command, 'description' => 'zbxapi-spec upserted', 'scriptid' => found['scriptid'] }]])
    end

    it 'creates without any id when no script carries the name yet' do
      creation = Fixtures.exchange('scripts/crud', 'script.create', 8)
      fresh = creation['params'].first['name']
      fake = FakeClient.new([Fixtures.exchange('scripts/crud', 'script.get', 15), creation])

      expect(described_class.new(fake).create_or_update(name: fresh, scope: 1, type: 0, command: command)).to eq(creation['result']['scriptids'].first.to_i)
      expect(fake.sent('script.create')).to eq([[{ 'name' => fresh, 'scope' => 1, 'type' => 0, 'command' => command }]])
      expect(fake.count('script.update')).to eq(0)
    end
  end

  describe '#get_or_create' do
    it 'returns the id the lookup found and creates nothing' do
      lookup = Fixtures.exchange('scripts/crud', 'script.get', 16)
      found = lookup['result'].first
      fake = FakeClient.new([lookup])

      expect(described_class.new(fake).get_or_create(name: found['name'], scope: 1, type: 0, command: command)).to eq(found['scriptid'].to_i)
      expect(fake.count('script.create')).to eq(0)
    end

    it 'creates when the lookup finds nothing and returns the new id' do
      creation = Fixtures.exchange('scripts/crud', 'script.create', 9)
      fresh = creation['params'].first['name']
      fake = FakeClient.new([Fixtures.exchange('scripts/crud', 'script.get', 17), creation])

      expect(described_class.new(fake).get_or_create(name: fresh, scope: 1, type: 0, command: command)).to eq(creation['result']['scriptids'].first.to_i)
      expect(fake.sent('script.get')).to eq([{ 'filter' => { 'name' => fresh }, 'output' => %w[scriptid name] }])
      expect(fake.sent('script.create')).to eq([[{ 'name' => fresh, 'scope' => 1, 'type' => 0, 'command' => command }]])
    end
  end

  describe '#delete' do
    it 'sends the bare id inside an Array and returns an Integer, although script.delete answered a String' do
      sent_id = deleted['params'].first
      expect([sent_id, deleted['result']['scriptids'].first]).to match([an_instance_of(Integer), an_instance_of(String)])

      fake = FakeClient.new([deleted])
      expect(described_class.new(fake).delete(sent_id)).to eq(sent_id)
      expect(fake.sent('script.delete')).to eq([[sent_id]])
    end
  end

  describe 'a name that two scripts carry under different menu paths' do
    it 'collapses in all and makes get_id refuse' do
      lookup_name = duplicated['result'].first['name']
      expect(table.count { |script| script['name'] == lookup_name }).to eq(2)

      whole_table = described_class.new(FakeClient.new([Fixtures.exchange('scripts/crud', 'script.get', 6)])).all
      expect(whole_table[lookup_name]).to eq(table.select { |script| script['name'] == lookup_name }.last['scriptid'].to_i)
      ids = duplicated['result'].map { |script| script['scriptid'] }.uniq
      expect { described_class.new(FakeClient.new([duplicated])).get_id(name: lookup_name) }.to raise_error(ZabbixApi::ApiError, /\Aget_id matched #{ids.size} script objects, not one \(scriptid #{ids.join(', ')}\): narrow the lookup\z/)
    end
  end

  describe '#execute' do
    it 'sends the scriptid and the hostid alone, with no null for the eventid and the manualinput it was not given' do
      fake = FakeClient.new([ran])
      described_class.new(fake).execute(scriptid: script_id, hostid: host_id)
      expect(fake.sent('script.execute').last).to eq('scriptid' => script_id, 'hostid' => host_id)
    end

    it 'sends the scriptid, the eventid and the manualinput, with no null for the hostid it was not given' do
      # Scripted, not recorded: the recorder executes only against a host of its own and owns no
      # event, the standing problem being only read. The answer has the shape the script.execute
      # reference's own example shows for a non-webhook script.
      fake = FakeClient.new([{ method: 'script.execute', result: { 'response' => 'success', 'value' => 'zbxapi', 'debug' => [] } }])
      described_class.new(fake).execute(scriptid: script_id, eventid: 25, manualinput: 'zbxapi')
      expect(fake.sent('script.execute').last).to eq('scriptid' => script_id, 'eventid' => 25, 'manualinput' => 'zbxapi')
    end

    it 'returns the webhook answer unwrapped, its debug an object with logs and ms' do
      result = described_class.new(FakeClient.new([ran])).execute(scriptid: script_id, hostid: host_id)
      expect(result).to eq(ran['result'])
      expect(result['response']).to eq('success')
      expect(result['debug'].keys).to match_array(%w[logs ms])
      expect(result['debug']['logs'].first.keys).to match_array(%w[level ms message])
    end

    it "returns a non-webhook answer whose debug is an empty Array, as the script.execute reference's own example shows and its text denies" do
      shell = Fixtures.exchange('scripts/execute', 'script.execute', 1)
      result = described_class.new(FakeClient.new([shell])).execute(scriptid: shell['params']['scriptid'], hostid: host_id)
      expect(result['debug']).to eq([])
      expect(result['value']).to eq("zbxapi\n")
    end

    it 'sends the hostid alone when no scriptid was given and lets the server refuse it' do
      refusal = Fixtures.exchange('scripts/execute', 'script.execute', 8)
      fake = FakeClient.new([refusal])

      expect { described_class.new(fake).execute(hostid: host_id) }
        .to raise_error(ZabbixApi::ApiError) { |error| expect(error.error_message).to match(/the parameter "scriptid" is missing/) }
      expect(fake.sent('script.execute')).to eq([{ 'hostid' => host_id }])
    end

    it 'raises ApiError carrying the server reason in error_message, for a refused execute' do
      [
        [3, /Provided script user input failed validation/],
        [4, /Cannot execute URL type script/],
        [5, /not allowed in manual host action/],
        [6, /No interface defined for host/],
        [7, /No permissions to referred object/],
        [9, /the parameter "eventid" is missing/]
      ].each do |index, reason|
        exchange = Fixtures.exchange('scripts/execute', 'script.execute', index)
        expect { described_class.new(FakeClient.new([exchange])).execute(exchange['params']) }
          .to raise_error(ZabbixApi::ApiError) { |error| expect(error.error_message).to match(reason) }
      end
    end
  end

  describe '#getscriptsbyhost' do
    it 'calls the plural API method and passes an object through unchanged' do
      fake = FakeClient.new([offered])
      described_class.new(fake).getscriptsbyhost(hostid: host_id)
      expect(fake.calls.map { |call| call['method'] }).to eq(['script.getscriptsbyhosts'])
      expect(fake.sent('script.getscriptsbyhosts')).to eq([{ 'hostid' => host_id }])
    end

    it 'passes an array of objects through unchanged' do
      exchange = Fixtures.exchange('scripts/execute', 'script.getscriptsbyhosts', 1)
      fake = FakeClient.new([exchange])
      described_class.new(fake).getscriptsbyhost([{ hostid: host_id }])
      expect(fake.sent('script.getscriptsbyhosts')).to eq([[{ 'hostid' => host_id }]])
    end

    it 'returns the object keyed by host id, holding the webhook execute ran and not the foreign-group script it refused' do
      refused_elsewhere = Fixtures.exchange('scripts/execute', 'script.execute', 7)['params']['scriptid']
      result = described_class.new(FakeClient.new([offered])).getscriptsbyhost(hostid: host_id)

      expect(result.keys).to eq([host_id.to_s])
      expect(result[host_id.to_s].map { |script| script['scriptid'] }).to include(script_id.to_s)
      expect(result[host_id.to_s].map { |script| script['scriptid'] }).not_to include(refused_elsewhere.to_s)
    end

    it 'narrows to the one script a scriptid names' do
      exchange = Fixtures.exchange('scripts/execute', 'script.getscriptsbyhosts', 2)
      result = described_class.new(FakeClient.new([exchange])).getscriptsbyhost(hostid: host_id, scriptid: script_id)
      expect(result[host_id.to_s].map { |script| script['scriptid'] }).to eq([script_id.to_s])
    end

    it 'returns the empty Array the server answers an empty object with, where the script.getscriptsbyhosts reference promises an object' do
      exchange = Fixtures.exchange('scripts/execute', 'script.getscriptsbyhosts', 5)
      fake = FakeClient.new([exchange])
      expect(described_class.new(fake).getscriptsbyhost({})).to eq([])
      expect(fake.sent('script.getscriptsbyhosts')).to eq([{}])
    end

    it 'raises the refusal of a bare array of host ids' do
      exchange = Fixtures.exchange('scripts/execute', 'script.getscriptsbyhosts', 4)
      expect { described_class.new(FakeClient.new([exchange])).getscriptsbyhost([host_id]) }
        .to raise_error(ZabbixApi::ApiError) { |error| expect(error.error_message).to match(/an array is expected/) }
    end
  end

  describe '#getscriptsbyevents' do
    it 'calls the API method under its own plural spelling and passes an object through unchanged' do
      fake = FakeClient.new([by_event])
      described_class.new(fake).getscriptsbyevents(eventid: event_id)
      expect(fake.calls.map { |call| call['method'] }).to eq(['script.getscriptsbyevents'])
      expect(fake.sent('script.getscriptsbyevents')).to eq([{ 'eventid' => event_id }])
    end

    it 'passes an array of objects through unchanged' do
      exchange = Fixtures.exchange('scripts/byevents', 'script.getscriptsbyevents', 1)
      fake = FakeClient.new([exchange])
      described_class.new(fake).getscriptsbyevents([{ eventid: event_id }])
      expect(fake.sent('script.getscriptsbyevents')).to eq([[{ 'eventid' => event_id }]])
    end

    it 'returns the object keyed by the event id as a String, holding the scope 4 script' do
      result = described_class.new(FakeClient.new([by_event])).getscriptsbyevents(eventid: event_id)
      expect(result.keys).to eq([event_id.to_s])
      expect(result[event_id.to_s].map { |script| script['scriptid'] }).to include(event_script.to_s)
    end

    it 'lists scripts of scope 1 and 2 beside the scope 4 one' do
      rows = described_class.new(FakeClient.new([by_event])).getscriptsbyevents(eventid: event_id)[event_id.to_s]
      expect(rows.map { |script| script['scope'] }.uniq).to match_array(%w[1 2 4])
    end

    it 'narrows to the one script a scriptid names' do
      exchange = Fixtures.exchange('scripts/byevents', 'script.getscriptsbyevents', 2)
      result = described_class.new(FakeClient.new([exchange])).getscriptsbyevents(eventid: event_id, scriptid: event_script)
      expect(result[event_id.to_s].map { |script| script['scriptid'] }).to eq([event_script.to_s])
    end

    it 'returns the empty Array the server answers an empty object with, where the script.getscriptsbyevents reference promises an object' do
      exchange = Fixtures.exchange('scripts/byevents', 'script.getscriptsbyevents', 4)
      fake = FakeClient.new([exchange])
      expect(described_class.new(fake).getscriptsbyevents({})).to eq([])
      expect(fake.sent('script.getscriptsbyevents')).to eq([{}])
    end

    it 'raises the refusal of a bare array of event ids' do
      exchange = Fixtures.exchange('scripts/byevents', 'script.getscriptsbyevents', 3)
      expect { described_class.new(FakeClient.new([exchange])).getscriptsbyevents([event_id]) }
        .to raise_error(ZabbixApi::ApiError) { |error| expect(error.error_message).to match(/an array is expected/) }
    end
  end

  describe 'a request the server refuses' do
    it 'raises ApiError carrying the server reason in error_message, for a refused create and delete' do
      [
        ['script.create', 1, /already exists/],
        ['script.create', 2, /unexpected parameter "scriptid"/],
        ['script.create', 3, /value must be one of 0, 1, 2, 3, 5/],
        ['script.create', 4, /menu_path": value must be empty/],
        ['script.delete', 1, /is used in action operation/],
        ['script.delete', 3, /No permissions to referred object/]
      ].each do |method, index, reason|
        exchange = Fixtures.exchange('scripts/crud', method, index)
        refused = described_class.new(FakeClient.new([exchange]))
        expect { method == 'script.create' ? refused.create(exchange['params'].first) : refused.delete(exchange['params'].first) }
          .to raise_error(ZabbixApi::ApiError) { |error| expect(error.error_message).to match(reason) }
      end
    end
  end
end
