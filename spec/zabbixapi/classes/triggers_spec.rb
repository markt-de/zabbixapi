# Contract: ZabbixApi::Triggers
#   evidence: spec/fixtures/triggers/crud.json;
#             https://www.zabbix.com/documentation/7.0/en/manual/api/reference/trigger
#   classes:  hooks | create wraps one object, merges no defaults and carries a collection | the
#             reads and what each sends | dump_by_id adds expandExpression and the two selects, so
#             the expression comes back in the form the caller wrote | update compares against that
#             dump, skips equal, issues differing, force, never skips tags, refuses without an id |
#             replace: no-op when equal, delete then create when not, a collection forces the
#             replacement, a missing trigger raises before any write | get_or_create scopes the
#             lookup by hostid and strips it from the create | create_or_update updates in place,
#             stripping the hostid from both branches | get_id refuses when two rows match, a hostid
#             narrows it | all collapses a description two triggers share | aliases | delete sends a
#             bare id and returns an Integer | refusals: duplicate description and expression,
#             hostid on create, the recovery pair, an enum bound, an unknown id, blind lookups
#   not here: all against the real table, which would pull every trigger on the server into the
#             fixture - two scripted rows stand for it; the further documented get parameters and
#             selects, server behaviour that belongs to the live spec, one get_raw representative
#             kept; dependencies, template triggers and inherited entities, which only a server can
#             show; bulk arrays, which Basic#create and #delete handle and Basic's own spec covers
require 'spec_helper'

RSpec.describe ZabbixApi::Triggers do
  crud = Fixtures.exchanges('triggers/crud')
  created = Fixtures.exchange('triggers/crud', 'trigger.create')
  # The description and expression as the caller wrote them, from the recorded request: a plain read
  # answers the expression with functionid references instead.
  description = created['params'].first['description']
  written = created['params'].first['expression']
  twins = Fixtures.exchange('triggers/crud', 'trigger.get')['result']
  row = twins.first
  dump = Fixtures.exchange('triggers/crud', 'trigger.get', 4)['result']
  deleted = Fixtures.exchange('triggers/crud', 'trigger.delete', 1)
  id = row['triggerid'].to_i
  # The host the trigger's item lives on, which is what the upserts scope by.
  hostid = dump.first['items'].first['hostid'].to_i

  let(:client) { FakeClient.new(crud) }
  let(:triggers) { described_class.new(client) }

  it_behaves_like 'a Basic resource', method_name: 'trigger', identify: 'description', key: 'triggerid', keys: 'triggerids', default_options: {}

  it_behaves_like 'an inherited create', payload: { description: description, expression: written }, defaults: {}, exchange: created
  it_behaves_like 'an inherited delete', id: deleted['result']['triggerids'].first.to_i, exchange: deleted
  it_behaves_like 'an inherited get_id', identify: 'description', key: 'triggerid', value: description, rows: [row]
  it_behaves_like 'an inherited all', identify: 'description', key: 'triggerid', rows: twins
  # dump_by_id is the class's own, below.
  it_behaves_like 'the inherited reads', identify: 'description', key: 'triggerid', value: description, id: id, rows: twins, except: [:dump_by_id]
  it_behaves_like 'an update that skips when unchanged', key: 'triggerid', id: id, dump: dump, unchanged: { description: description }, changed: { comments: 'changed offline' }, collection: { tags: [{ tag: 'zbxapi-spec', value: 'triggers' }] }

  # Both upserts scope the lookup by hostid and strip it from every write: trigger.create refuses a
  # hostid as an unexpected parameter, which is why strip_on_create is true here.
  it_behaves_like 'a host-scoped upsert',
                  identify: 'description', key: 'triggerid', hostid: hostid,
                  payload: { description: description, expression: written, hostid: hostid, priority: 5 },
                  found: Fixtures.exchange('triggers/crud', 'trigger.get', 15)['result'],
                  update_result: Fixtures.exchange('triggers/crud', 'trigger.update', 3)['result'],
                  create_result: Fixtures.exchange('triggers/crud', 'trigger.create', 9)['result'],
                  strip_on_create: true

  it_behaves_like 'the aliases', exchanges: crud, payload: { description: description, expression: written }, id: id

  it_behaves_like 'a lookup that refuses to run blind', method: :dump_by_id, field: 'triggerid'
  it_behaves_like 'a lookup that refuses to run blind', method: :get_id, field: 'description'

  # One instance per normalisation mechanism: the three inherited paths that differ - the plain
  # symbolize_keys of a filter-building read, the conditional one in get_id, the dump comparison in
  # update - plus every entry point this class defines itself. create is not a fourth inherited one,
  # because without default_options it is the same mechanism as get_full_data.
  it_behaves_like 'a key-normalising entry point', method: :get_full_data, payload: { description: description }, exchanges: crud
  it_behaves_like 'a key-normalising entry point', method: :update, payload: { triggerid: id, comments: 'changed offline' }, exchanges: crud
  it_behaves_like 'a key-normalising entry point', method: :dump_by_id, payload: { triggerid: id }, exchanges: crud
  it_behaves_like 'a key-normalising entry point', method: :replace, payload: { triggerid: id, description: description }, exchanges: crud
  # trigger.get[0] is the unscoped two-row answer FakeClient would hand these three first, and
  # get_id refuses it, so each gets its scoped lookup. create_or_update updates in place, so it
  # consumes three: its lookup, then the dump and update #update's example replays.
  it_behaves_like 'a key-normalising entry point', method: :get_id, payload: { description: description, hostid: hostid }, exchanges: [Fixtures.exchange('triggers/crud', 'trigger.get', 1)]
  it_behaves_like 'a key-normalising entry point', method: :get_or_create, payload: { description: description, expression: written, hostid: hostid }, exchanges: [Fixtures.exchange('triggers/crud', 'trigger.get', 13)]
  it_behaves_like 'a key-normalising entry point', method: :create_or_update, payload: { description: description, expression: written, hostid: hostid }, exchanges: [Fixtures.exchange('triggers/crud', 'trigger.get', 15), Fixtures.exchange('triggers/crud', 'trigger.get', 6), Fixtures.exchange('triggers/crud', 'trigger.update')]

  describe '#create' do
    it 'sends one object with every property the caller gave, the tags among them, and adds nothing' do
      payload = { description: "#{description}-full", expression: written, event_name: 'evt {HOST.NAME}', opdata: 'op', comments: 'a comment', priority: 5, status: 1, type: 1, url: 'http://example.invalid/', url_name: 'runbook', manual_close: 1, tags: [{ tag: 'zbxapi-spec', value: 'triggers' }] }
      full = Fixtures.exchange('triggers/crud', 'trigger.create', 3)
      fake = FakeClient.new([full])

      expect(described_class.new(fake).create(payload)).to eq(full['result']['triggerids'].first.to_i)
      expect(fake.sent('trigger.create')).to eq([[JSON.parse(JSON.generate(payload))]])
    end
  end

  describe '#dump_by_id' do
    it 'filters on the triggerid and asks for extend, the expanded expression and the two selects' do
      triggers.dump_by_id(triggerid: id)
      expect(client.sent('trigger.get').last).to eq('filter' => { 'triggerid' => id }, 'output' => 'extend', 'expandExpression' => true, 'selectItems' => 'extend', 'selectFunctions' => 'extend')
    end

    it 'returns the expression in the form the caller wrote, where a plain extend read returns a functionid reference' do
      expect(row['expression']).to match(/\A\{\d+\}/)
      dumped = described_class.new(FakeClient.new([Fixtures.exchange('triggers/crud', 'trigger.get', 4)])).dump_by_id(triggerid: id)
      expect(dumped.first['expression']).to eq(written)
      expect(dumped.first).to include('items', 'functions')
    end
  end

  describe '#update' do
    it 'reads the expanded dump first and issues one update carrying the id and the changed field' do
      fake = FakeClient.new([Fixtures.exchange('triggers/crud', 'trigger.get', 6), Fixtures.exchange('triggers/crud', 'trigger.update')])

      expect(described_class.new(fake).update(triggerid: id, comments: 'recorded update')).to eq(id)
      expect(fake.calls.map { |call| call['method'] }).to eq(%w[trigger.get trigger.update])
      expect(fake.sent('trigger.get').first).to include('expandExpression' => true)
      expect(fake.sent('trigger.update')).to eq([[{ 'triggerid' => id, 'comments' => 'recorded update' }]])
    end

    it 'raises before any request when the payload names no triggerid' do
      expect { triggers.update(comments: 'changed offline') }.to raise_error(ZabbixApi::ApiError, /triggerid not supplied in call to dump_by_id/)
      expect(client.calls).to be_empty
    end
  end

  describe '#replace' do
    made = Fixtures.exchange('triggers/crud', 'trigger.create', 7)
    stored = { description: made['params'].first['description'], expression: written, priority: made['params'].first['priority'] }
    safe_id = made['result']['triggerids'].first.to_i
    replaced = Fixtures.exchange('triggers/crud', 'trigger.create', 8)

    it 'returns the id and writes nothing when every supplied field already matches the dump' do
      fake = FakeClient.new([Fixtures.exchange('triggers/crud', 'trigger.get', 10)])

      expect(described_class.new(fake).replace(stored.merge(triggerid: safe_id))).to eq(safe_id)
      expect(fake.calls.map { |call| call['method'] }).to eq(%w[trigger.get])
    end

    it 'deletes the old trigger first and then creates the new one, without the triggerid or a templateid' do
      fake = FakeClient.new([Fixtures.exchange('triggers/crud', 'trigger.get', 11), Fixtures.exchange('triggers/crud', 'trigger.delete'), replaced])
      renamed = stored.merge(triggerid: safe_id, templateid: 0, description: replaced['params'].first['description'])

      expect(described_class.new(fake).replace(renamed)).to eq(replaced['result']['triggerids'].first.to_i)
      expect(fake.calls.map { |call| call['method'] }).to eq(%w[trigger.get trigger.delete trigger.create])
      expect(fake.sent('trigger.delete')).to eq([[safe_id]])
      expect(fake.sent('trigger.create')).to eq([[JSON.parse(JSON.generate(stored.merge(description: replaced['params'].first['description'])))]])
    end

    it 'issues one create carrying the tags although every scalar matches, when the payload names tags' do
      fake = FakeClient.new([Fixtures.exchange('triggers/crud', 'trigger.get', 10), Fixtures.exchange('triggers/crud', 'trigger.delete'), replaced])

      described_class.new(fake).replace(stored.merge(triggerid: safe_id, tags: [{ tag: 'zbxapi-spec', value: 'triggers' }]))
      expect(fake.count('trigger.create')).to eq(1)
      expect(fake.sent('trigger.create').first.first).to include('tags' => [{ 'tag' => 'zbxapi-spec', 'value' => 'triggers' }])
    end

    it 'raises after the dump and before any write when no trigger carries that id' do
      fake = FakeClient.new([Fixtures.exchange('triggers/crud', 'trigger.get', 12)])

      expect { described_class.new(fake).replace(stored.merge(triggerid: 999999999)) }.to raise_error(ZabbixApi::ApiError, /Trigger 999999999 not found, cannot replace it/)
      expect(fake.calls.map { |call| call['method'] }).to eq(%w[trigger.get])
    end
  end

  describe '#get_or_create' do
    it 'looks the description up scoped by hostid and returns the existing id without creating' do
      found = Fixtures.exchange('triggers/crud', 'trigger.get', 13)
      fake = FakeClient.new([found])

      expect(described_class.new(fake).get_or_create(description: description, expression: written, hostid: hostid)).to eq(found['result'].first['triggerid'].to_i)
      expect(fake.sent('trigger.get')).to eq([{ 'filter' => { 'description' => description, 'hostid' => hostid }, 'output' => %w[triggerid description] }])
      expect(fake.count('trigger.create')).to eq(0)
    end

    it 'creates without the hostid when nothing matches' do
      made = Fixtures.exchange('triggers/crud', 'trigger.create', 9)
      fresh = made['params'].first['description']
      fake = FakeClient.new([Fixtures.exchange('triggers/crud', 'trigger.get', 14), made])

      expect(described_class.new(fake).get_or_create(description: fresh, expression: written, hostid: hostid)).to eq(made['result']['triggerids'].first.to_i)
      expect(fake.sent('trigger.create')).to eq([[{ 'description' => fresh, 'expression' => written }]])
    end
  end

  describe '#create_or_update' do
    payload = { description: description, expression: written, hostid: hostid, priority: 5 }

    it 'creates without the hostid when the lookup finds nothing' do
      made = Fixtures.exchange('triggers/crud', 'trigger.create', 9)
      fresh = made['params'].first['description']
      fake = FakeClient.new([Fixtures.exchange('triggers/crud', 'trigger.get', 14), made])

      expect(described_class.new(fake).create_or_update(description: fresh, expression: written, hostid: hostid)).to eq(made['result']['triggerids'].first.to_i)
      expect(fake.sent('trigger.create')).to eq([[{ 'description' => fresh, 'expression' => written }]])
    end

    it 'updates the trigger the lookup found, the triggerid merged in and the hostid stripped' do
      found = Fixtures.exchange('triggers/crud', 'trigger.get', 15)
      updated = Fixtures.exchange('triggers/crud', 'trigger.update')
      fake = FakeClient.new([found, Fixtures.exchange('triggers/crud', 'trigger.get', 6), updated])

      expect(described_class.new(fake).create_or_update(payload)).to eq(updated['result']['triggerids'].first.to_i)
      expect(fake.calls.map { |call| call['method'] }).to eq(%w[trigger.get trigger.get trigger.update])
      expect(fake.sent('trigger.update').last.first).to eq('description' => description, 'expression' => written, 'priority' => 5, 'triggerid' => found['result'].first['triggerid'].to_i)
    end
  end

  describe '#get_id' do
    it 'refuses to choose between two rows under one description' do
      expect(twins.map { |trigger| trigger['description'] }.uniq).to eq([description])
      fake = FakeClient.new([{ method: 'trigger.get', params: {}, result: twins }])

      expect { described_class.new(fake).get_id(description: description) }.to raise_error(ZabbixApi::ApiError, /\Aget_id matched 2 trigger objects, not one \(triggerid #{twins.map { |trigger| trigger['triggerid'] }.join(', ')}\): narrow the lookup\z/)
    end

    it 'narrows the lookup to that host when a hostid scopes the filter, which the trigger.get reference documents' do
      scoped = Fixtures.exchange('triggers/crud', 'trigger.get', 1)
      fake = FakeClient.new([scoped])

      expect(described_class.new(fake).get_id(description: description, hostid: hostid)).to eq(scoped['result'].first['triggerid'].to_i)
      expect(fake.sent('trigger.get')).to eq([{ 'filter' => { 'description' => description, 'hostid' => hostid }, 'output' => %w[triggerid description] }])
    end
  end

  describe '#all' do
    it 'keeps one key for a description two triggers share, and the last row wins' do
      expect(twins.map { |trigger| trigger['triggerid'] }.uniq.size).to eq(2)
      fake = FakeClient.new([{ method: 'trigger.get', params: {}, result: twins }])

      expect(described_class.new(fake).all).to eq(description => twins.last['triggerid'].to_i)
    end
  end

  describe 'a request the server refuses' do
    it 'raises ApiError carrying the server reason in error_message, for a refused create and delete' do
      [
        # a duplicate description plus expression on one host
        [Fixtures.exchange('triggers/crud', 'trigger.create', 2), /already exists on/, ->(wrapper) { wrapper.create(description: description, expression: written) }],
        # hostid, the reason the upserts strip it before the create
        [Fixtures.exchange('triggers/crud', 'trigger.create', 6), /unexpected parameter "hostid"/, ->(wrapper) { wrapper.create(description: description, expression: written, hostid: hostid) }],
        # recovery_mode 1 without a recovery_expression, worded "Incorrect value for field" where
        # the priority and hostid refusals say "Invalid parameter"
        [Fixtures.exchange('triggers/crud', 'trigger.create', 4), /"recovery_expression": cannot be empty/, ->(wrapper) { wrapper.create(description: description, expression: written, recovery_mode: 1) }],
        # priority outside the documented 0-5
        [Fixtures.exchange('triggers/crud', 'trigger.create', 5), /value must be one of 0, 1, 2, 3, 4, 5/, ->(wrapper) { wrapper.create(description: description, expression: written, priority: 6) }],
        # a triggerid no trigger carries
        [Fixtures.exchange('triggers/crud', 'trigger.delete', 3), /No permissions to referred object/, ->(wrapper) { wrapper.delete(999999999) }]
      ].each do |exchange, reason, call|
        expect { call.call(described_class.new(FakeClient.new([exchange]))) }
          .to raise_error(ZabbixApi::ApiError) { |error| expect(error.error_message).to match(reason) }
      end
    end
  end
end
