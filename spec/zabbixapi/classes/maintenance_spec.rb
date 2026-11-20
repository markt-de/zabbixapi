# Contract: ZabbixApi::Maintenance
#   evidence: spec/fixtures/maintenance/crud.json;
#             https://www.zabbix.com/documentation/7.0/en/manual/api/reference/maintenance
#   classes:  hooks, the class overriding no other method | create wraps one object and merges no
#             defaults | a create carrying all four collections reaches the wire untouched | the
#             four reads and what each sends | all maps the name to an Integer id | update skips
#             equal, issues differing, issues for a collection the dump cannot show, force | update
#             refuses without an id | the four upsert branches, the id merged in as a String | the
#             three aliases | delete sends a bare id and returns an Integer whether the answer holds
#             an Integer or a String | key normalisation, four entry points and four mechanisms | a
#             server refusal reaches error_message
#   not here: the object's own validation - the two enum holes, the gated time-period properties,
#             the conditional sub-fields, the period range, the minute truncation - which is the
#             server's and is asserted live, two of those refusals, the timeperiod_type hole and
#             start_time on a one-time period, sitting recorded in the fixture; the deprecated
#             groupids and hostids, a passthrough with nothing gem-side to assert; the four select*
#             and sortfield, server behaviour asserted live; bulk arrays, which Basic#create and
#             #delete handle and Basic's own spec covers
require 'spec_helper'

RSpec.describe ZabbixApi::Maintenance do
  crud = Fixtures.exchanges('maintenance/crud')
  row = Fixtures.exchange('maintenance/crud', 'maintenance.get')['result'].first
  table = Fixtures.exchange('maintenance/crud', 'maintenance.get', 5)['result']
  deleted = Fixtures.exchange('maintenance/crud', 'maintenance.delete')
  id = row['maintenanceid'].to_i
  name = row['name']
  # The five things a create needs at once, as the maintenance object and maintenance.create
  # references require them. The ids are arbitrary offline: FakeClient replays by method and never
  # looks at them.
  minimal = { name: name, active_since: row['active_since'].to_i, active_till: row['active_till'].to_i, groups: [{ groupid: 1 }], timeperiods: [{ timeperiod_type: 0, period: 3600 }] }

  let(:client) { FakeClient.new(crud) }
  let(:maintenance) { described_class.new(client) }

  it_behaves_like 'a Basic resource', method_name: 'maintenance', identify: 'name', key: 'maintenanceid', keys: 'maintenanceids', default_options: {}

  it_behaves_like 'an inherited create', payload: minimal, defaults: {}, exchange: Fixtures.exchange('maintenance/crud', 'maintenance.create')
  it_behaves_like 'an inherited delete', id: deleted['result']['maintenanceids'].first, exchange: deleted
  it_behaves_like 'an inherited get_id', identify: 'name', key: 'maintenanceid', value: name, rows: [row]
  it_behaves_like 'an inherited all', identify: 'name', key: 'maintenanceid', rows: table
  it_behaves_like 'the inherited reads', identify: 'name', key: 'maintenanceid', value: name, id: id, rows: [row]
  # groups, hosts, timeperiods and tags are never in output: extend, so a payload naming one can
  # never be proven equal to the stored state and the call always goes out.
  it_behaves_like 'an update that skips when unchanged', key: 'maintenanceid', id: id, dump: [row], unchanged: { name: name }, changed: { description: 'erste' }, collection: { groups: [{ groupid: 1 }] }
  it_behaves_like 'the aliases', exchanges: crud, payload: { name: name }, id: id

  it_behaves_like 'a lookup that refuses to run blind', method: :dump_by_id, field: 'maintenanceid'
  it_behaves_like 'a lookup that refuses to run blind', method: :get_id, field: 'name'

  # One instance per normalisation mechanism, not per entry point: the plain symbolize_keys of a
  # filter-building read, the conditional one in get_id, require_field! in dump_by_id, and the dump
  # comparison in update. create would be a fifth only for a class with default_options; without
  # them it is the same mechanism as get_full_data.
  it_behaves_like 'a key-normalising entry point', method: :get_full_data, payload: { name: name }, exchanges: crud
  it_behaves_like 'a key-normalising entry point', method: :get_id, payload: { name: name }, exchanges: crud
  it_behaves_like 'a key-normalising entry point', method: :dump_by_id, payload: { maintenanceid: id }, exchanges: crud
  it_behaves_like 'a key-normalising entry point', method: :update, payload: { maintenanceid: id, name: name }, exchanges: crud

  describe '#create' do
    it 'passes all four collections and the nested time periods through untouched' do
      rich = FakeClient.new([Fixtures.exchange('maintenance/crud', 'maintenance.create', 7)])
      payload = {
        name: "#{name}-rich",
        description: 'every collection at once',
        active_since: minimal[:active_since],
        active_till: minimal[:active_till],
        maintenance_type: 0,
        tags_evaltype: 2,
        groups: [{ groupid: 1 }, { groupid: 2 }],
        hosts: [{ hostid: 3 }],
        tags: [{ tag: 'service', operator: 0, value: 'mysqld' }, { tag: 'error', operator: 2, value: '' }],
        timeperiods: [{ timeperiod_type: 0, period: 3600 },
                      { timeperiod_type: 2, period: 3600, start_time: 3600, every: 1 },
                      { timeperiod_type: 3, period: 3600, start_time: 3600, every: 1, dayofweek: 64 },
                      { timeperiod_type: 4, period: 3600, start_time: 3600, every: 1, dayofweek: 64, month: 1 }]
      }

      described_class.new(rich).create(payload)
      expect(rich.sent('maintenance.create')).to eq([[JSON.parse(JSON.generate(payload))]])
    end
  end

  describe '#update' do
    it 'raises before any request when the payload names no maintenanceid' do
      expect { maintenance.update(name: name) }.to raise_error(ZabbixApi::ApiError, /maintenanceid not supplied in call to dump_by_id/)
      expect(client.calls).to be_empty
    end
  end

  describe '#create_or_update' do
    it 'looks the name up, dumps the object and updates it with the id merged in as a String' do
      fake = FakeClient.new([Fixtures.exchange('maintenance/crud', 'maintenance.get', 10), Fixtures.exchange('maintenance/crud', 'maintenance.get', 11), Fixtures.exchange('maintenance/crud', 'maintenance.update', 3)])

      expect(described_class.new(fake).create_or_update(name: name, description: 'per upsert')).to eq(id)
      expect(fake.sent('maintenance.get')).to eq([{ 'filter' => { 'name' => name }, 'output' => %w[maintenanceid name] }, { 'filter' => { 'maintenanceid' => id.to_s }, 'output' => 'extend' }])
      expect(fake.sent('maintenance.update')).to eq([[{ 'name' => name, 'description' => 'per upsert', 'maintenanceid' => id.to_s }]])
    end

    it 'creates the whole payload unchanged when no maintenance carries that name' do
      created = Fixtures.exchange('maintenance/crud', 'maintenance.create', 8)
      fake = FakeClient.new([Fixtures.exchange('maintenance/crud', 'maintenance.get', 12), created])
      payload = minimal.merge(name: "#{name}-upserted")

      expect(described_class.new(fake).create_or_update(payload)).to eq(created['result']['maintenanceids'].first.to_i)
      expect(fake.sent('maintenance.create')).to eq([[JSON.parse(JSON.generate(payload))]])
      expect(fake.count('maintenance.update')).to eq(0)
    end
  end

  describe '#get_or_create' do
    it 'returns the id the lookup found and creates nothing' do
      fake = FakeClient.new([Fixtures.exchange('maintenance/crud', 'maintenance.get', 13)])

      expect(described_class.new(fake).get_or_create(name: name)).to eq(id)
      expect(fake.count('maintenance.create')).to eq(0)
    end

    it 'looks up by the name alone and creates when nothing matches' do
      created = Fixtures.exchange('maintenance/crud', 'maintenance.create', 9)
      fake = FakeClient.new([Fixtures.exchange('maintenance/crud', 'maintenance.get', 14), created])
      payload = minimal.merge(name: "#{name}-gotten")

      expect(described_class.new(fake).get_or_create(payload)).to eq(created['result']['maintenanceids'].first.to_i)
      expect(fake.sent('maintenance.get')).to eq([{ 'filter' => { 'name' => payload[:name] }, 'output' => %w[maintenanceid name] }])
      expect(fake.sent('maintenance.create')).to eq([[JSON.parse(JSON.generate(payload))]])
    end
  end

  describe '#delete' do
    it 'sends the bare id and returns an Integer, whether the answer holds an Integer or a String' do
      echoed_integer = deleted['result']['maintenanceids'].first
      echoed_string = Fixtures.exchange('maintenance/crud', 'maintenance.delete', 1)['result']['maintenanceids'].first
      expect([echoed_integer, echoed_string]).to match([an_instance_of(Integer), an_instance_of(String)])

      by_integer = FakeClient.new([deleted])
      by_string = FakeClient.new([Fixtures.exchange('maintenance/crud', 'maintenance.delete', 1)])
      expect(described_class.new(by_integer).delete(echoed_integer)).to eq(echoed_integer)
      expect(described_class.new(by_string).delete(echoed_string)).to eq(echoed_string.to_i)
      expect([by_integer.sent('maintenance.delete'), by_string.sent('maintenance.delete')]).to eq([[[echoed_integer]], [[echoed_string]]])
    end
  end

  describe 'a request the server refuses' do
    it 'raises ApiError carrying the server reason in error_message, for a refused create and delete' do
      [
        [Fixtures.exchange('maintenance/crud', 'maintenance.create', 1), /already exists/],
        [Fixtures.exchange('maintenance/crud', 'maintenance.create', 2), /the parameter "timeperiods" is missing/],
        [Fixtures.exchange('maintenance/crud', 'maintenance.create', 3), /At least one host group or host must be selected/],
        [Fixtures.exchange('maintenance/crud', 'maintenance.delete', 2), /No permissions to referred object/]
      ].each do |exchange, reason|
        refused = described_class.new(FakeClient.new([exchange]))
        expect { exchange['method'] == 'maintenance.create' ? refused.create(minimal) : refused.delete(id) }
          .to raise_error(ZabbixApi::ApiError) { |error| expect(error.error_message).to match(reason) }
      end
    end
  end
end
