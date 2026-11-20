# Contract: ZabbixApi::Hosts
#   evidence: spec/fixtures/hosts/crud.json;
#             https://www.zabbix.com/documentation/7.0/en/manual/api/reference/host,
#             https://www.zabbix.com/documentation/7.0/en/manual/api/reference/hostinterface
#   classes:  hooks | create wraps one object over four defaults, dropping the host placeholder when
#             omitted | the inherited reads and what each sends | all maps the technical name to an
#             Integer id | dump_by_id adds selectHostGroups | update turns the dump's hostgroups
#             into groups, sorts them by groupid as Integers, skips an equal set, issues a differing
#             one and a collection the dump cannot show, force | the four upsert branches, the id
#             merged in as a String | unlink_templates forwards two of six parameters, the templates
#             as templateids_clear under clear: true, and maps the result to a Boolean | the three
#             aliases | delete sends a bare id and returns an Integer, both recorded answers holding
#             a String | key normalisation, five entry points | refusals: a blind lookup, an update
#             without a hostid, four server refusals through error_message
#   not here: monitored_by, TLS and the six extra create parameters - server validation of
#             parameters the wrapper only passes through, which the acceptance spec asserts; the
#             read-only properties host.update accepts, of which the acceptance spec pins
#             maintenance_status as pending and never sends flags, an out-of-range flags value
#             making a host permanently unreachable; bulk arrays, which Basic#create and #delete
#             handle and Basic's own spec covers; host.massadd and host.massupdate, which the gem
#             does not wrap; the further documented get parameters, one get_raw representative kept
require 'spec_helper'

RSpec.describe ZabbixApi::Hosts do
  crud = Fixtures.exchanges('hosts/crud')
  defaults = { host: nil, interfaces: [], status: 0, groups: [] }

  row = Fixtures.exchange('hosts/crud', 'host.get')['result'].first
  dump = Fixtures.exchange('hosts/crud', 'host.get', 3)['result']
  two_groups = Fixtures.exchange('hosts/crud', 'host.get', 9)['result']
  table = Fixtures.exchange('hosts/crud', 'host.get', 5)['result']
  created = Fixtures.exchange('hosts/crud', 'host.create')
  removed = Fixtures.exchange('hosts/crud', 'host.delete')

  id = row['hostid'].to_i
  name = row['host']
  group = dump.first['hostgroups'].first['groupid'].to_i
  other_group = (two_groups.first['hostgroups'].map { |entry| entry['groupid'].to_i } - [group]).first

  let(:client) { FakeClient.new(crud) }
  let(:hosts) { described_class.new(client) }

  it_behaves_like 'a Basic resource', method_name: 'host', identify: 'host', key: 'hostid', keys: 'hostids', default_options: { host: nil, interfaces: [], status: 0, groups: [] }

  it_behaves_like 'an inherited create', payload: { host: name, groups: [{ groupid: group }] }, defaults: defaults, exchange: created
  it_behaves_like 'an inherited delete', id: removed['result']['hostids'].first.to_i, exchange: removed
  it_behaves_like 'an inherited get_id', identify: 'host', key: 'hostid', value: name, rows: Fixtures.exchange('hosts/crud', 'host.get', 1)['result']
  it_behaves_like 'an inherited all', identify: 'host', key: 'hostid', rows: table
  # dump_by_id is the one read Hosts overrides; its own examples are below.
  it_behaves_like 'the inherited reads', identify: 'host', key: 'hostid', value: name, id: id, rows: [row], except: [:dump_by_id]
  it_behaves_like 'the aliases', exchanges: crud, payload: { host: name }, id: id

  it_behaves_like 'a lookup that refuses to run blind', method: :dump_by_id, field: 'hostid'
  it_behaves_like 'a lookup that refuses to run blind', method: :get_id, field: 'host'

  # interfaces is the collection no output: extend returns, so a payload naming one is never skipped;
  # groups is the exception the selectHostGroups of dump_by_id buys, and has its own examples below.
  it_behaves_like 'an update that skips when unchanged', key: 'hostid', id: id, dump: dump, unchanged: { host: name }, changed: { description: 'desc v1' }, collection: { interfaces: [{ type: 1, main: 1, useip: 1, ip: '192.0.2.12', dns: '', port: '10050' }] }

  # One instance per normalisation mechanism: the merge over default_options in create, the
  # conditional symbolize_keys of get_id, and the three entry points Hosts defines itself.
  it_behaves_like 'a key-normalising entry point', method: :create, payload: { host: name, groups: [{ groupid: group }] }, exchanges: crud
  it_behaves_like 'a key-normalising entry point', method: :get_id, payload: { host: name }, exchanges: crud
  it_behaves_like 'a key-normalising entry point', method: :dump_by_id, payload: { hostid: id }, exchanges: crud
  it_behaves_like 'a key-normalising entry point', method: :unlink_templates, payload: { hosts_id: [id], templates_id: [10343] }, exchanges: crud
  # Through the issued branch, so that the reconciled groups are compared on the wire and not only
  # in the skip decision: the dump holds two groups, the payload one.
  it_behaves_like 'a key-normalising entry point', method: :update, payload: { hostid: id, groups: [{ groupid: group }] }, exchanges: [Fixtures.exchange('hosts/crud', 'host.get', 9), Fixtures.exchange('hosts/crud', 'host.update', 1)]

  describe '#create' do
    it "sends the injected interfaces and status beside the caller's groups and drops the unset host placeholder" do
      refused = FakeClient.new([Fixtures.exchange('hosts/crud', 'host.create', 2)])
      expect { described_class.new(refused).create(groups: [{ groupid: group }]) }.to raise_error(ZabbixApi::ApiError)
      expect(refused.sent('host.create').last).to eq([{ 'interfaces' => [], 'status' => 0, 'groups' => [{ 'groupid' => group }] }])
    end
  end

  describe '#dump_by_id' do
    it 'filters on the hostid, asks for extend and additionally selects the host groups' do
      hosts.dump_by_id(hostid: id)
      expect(client.sent('host.get').last).to eq('filter' => { 'hostid' => id }, 'output' => 'extend', 'selectHostGroups' => 'extend')
    end

    it 'returns rows carrying hostgroups, where the plain extend read of get_full_data has none' do
      dumped = described_class.new(FakeClient.new([Fixtures.exchange('hosts/crud', 'host.get', 3)])).dump_by_id(hostid: id)
      plain = described_class.new(FakeClient.new([Fixtures.exchange('hosts/crud', 'host.get')])).get_full_data(host: name)
      expect(dumped.first['hostgroups'].map { |entry| entry['groupid'].to_i }).to eq([group])
      expect(plain.first).not_to have_key('hostgroups')
    end
  end

  describe '#update' do
    it 'skips the request when the dump already holds that group set, given in another order and under string keys' do
      fake = FakeClient.new([Fixtures.exchange('hosts/crud', 'host.get', 9)])
      expect(described_class.new(fake).update(hostid: id, groups: [{ 'groupid' => other_group }, { 'groupid' => group }])).to eq(id)
      expect(fake.count('host.update')).to eq(0)
    end

    it 'issues the update with the groups sorted by groupid and their ids as Integers when the set differs' do
      fake = FakeClient.new([Fixtures.exchange('hosts/crud', 'host.get', 3), Fixtures.exchange('hosts/crud', 'host.update', 1)])
      expect(described_class.new(fake).update(hostid: id, groups: [{ groupid: other_group.to_s }, { groupid: group.to_s }])).to eq(id)
      expect(fake.sent('host.update')).to eq([[{ 'hostid' => id, 'groups' => [{ 'groupid' => group }, { 'groupid' => other_group }] }]])
    end

    it 'raises before any request when the payload names no hostid' do
      expect { hosts.update(host: name) }.to raise_error(ZabbixApi::ApiError, /hostid not supplied in call to dump_by_id/)
      expect(client.calls).to be_empty
    end
  end

  describe '#unlink_templates' do
    it 'forwards hostids and templateids only, dropping the templateids_clear, groupids, macros and interfaces the payload also names' do
      hosts.unlink_templates(hosts_id: [id], templates_id: [10343], templateids_clear: [10343], groupids: [group], macros: ['{$ZBXAPI_SPEC_HOSTS}'], interfaces: [{ ip: '192.0.2.12' }])
      expect(client.sent('host.massRemove').last).to eq('hostids' => [id], 'templateids' => [10343])
    end

    it 'forwards hostids and the templates as templateids_clear under clear: true' do
      hosts.unlink_templates(hosts_id: [id], templates_id: [10343], clear: true)
      expect(client.sent('host.massRemove').last).to eq('hostids' => [id], 'templateids_clear' => [10343])
    end

    it 'reports a filled result as true and an empty one as false, never the ids' do
      filled = described_class.new(FakeClient.new([Fixtures.exchange('hosts/crud', 'host.massRemove')]))
      empty = described_class.new(FakeClient.new([{ method: 'host.massRemove', result: {} }]))
      expect([filled.unlink_templates(hosts_id: [id], templates_id: [10343]), empty.unlink_templates(hosts_id: [id], templates_id: [10343])]).to eq([true, false])
    end
  end

  describe '#create_or_update' do
    it 'looks the technical name up, dumps by the id as a String and updates carrying it' do
      fake = FakeClient.new([Fixtures.exchange('hosts/crud', 'host.get', 12), Fixtures.exchange('hosts/crud', 'host.get', 13), Fixtures.exchange('hosts/crud', 'host.update', 4)])

      expect(described_class.new(fake).create_or_update(host: name, description: 'via upsert')).to eq(id)
      expect(fake.sent('host.get')).to eq([{ 'filter' => { 'host' => name }, 'output' => %w[hostid host] }, { 'filter' => { 'hostid' => id.to_s }, 'output' => 'extend', 'selectHostGroups' => 'extend' }])
      expect(fake.sent('host.update')).to eq([[{ 'host' => name, 'description' => 'via upsert', 'hostid' => id.to_s }]])
    end

    it 'creates over the defaults and updates nothing when no host carries that name' do
      creation = Fixtures.exchange('hosts/crud', 'host.create', 5)
      fake = FakeClient.new([Fixtures.exchange('hosts/crud', 'host.get', 14), creation])
      fresh = "#{name}-two"

      expect(described_class.new(fake).create_or_update(host: fresh, groups: [{ groupid: group }])).to eq(creation['result']['hostids'].first.to_i)
      expect(fake.sent('host.create')).to eq([[{ 'host' => fresh, 'interfaces' => [], 'status' => 0, 'groups' => [{ 'groupid' => group }] }]])
      expect(fake.count('host.update')).to eq(0)
    end
  end

  describe '#get_or_create' do
    it 'returns the id the lookup found and creates nothing' do
      found = Fixtures.exchange('hosts/crud', 'host.get', 15)
      fake = FakeClient.new([found])

      expect(described_class.new(fake).get_or_create(host: found['result'].first['host'])).to eq(found['result'].first['hostid'].to_i)
      expect(fake.count('host.create')).to eq(0)
    end

    it 'creates when the lookup finds nothing and returns the new id' do
      creation = Fixtures.exchange('hosts/crud', 'host.create', 6)
      fake = FakeClient.new([Fixtures.exchange('hosts/crud', 'host.get', 16), creation])
      fresh = "#{name}-three"

      expect(described_class.new(fake).get_or_create(host: fresh, groups: [{ groupid: group }])).to eq(creation['result']['hostids'].first.to_i)
      expect(fake.sent('host.get')).to eq([{ 'filter' => { 'host' => fresh }, 'output' => %w[hostid host] }])
      expect(fake.sent('host.create')).to eq([[{ 'host' => fresh, 'interfaces' => [], 'status' => 0, 'groups' => [{ 'groupid' => group }] }]])
    end
  end

  describe '#delete' do
    it 'sends the bare id and returns an Integer, both recorded answers holding a String' do
      by_integer = removed['result']['hostids'].first
      by_string = Fixtures.exchange('hosts/crud', 'host.delete', 1)['result']['hostids'].first
      expect([by_integer, by_string]).to all(be_a(String))

      integers = FakeClient.new([removed])
      strings = FakeClient.new([Fixtures.exchange('hosts/crud', 'host.delete', 1)])
      expect([described_class.new(integers).delete(by_integer.to_i), described_class.new(strings).delete(by_string)]).to eq([by_integer.to_i, by_string.to_i])
      expect([integers.sent('host.delete'), strings.sent('host.delete')]).to eq([[[by_integer.to_i]], [[by_string]]])
    end
  end

  describe 'a request the server refuses' do
    it 'raises ApiError carrying the server reason in error_message, for a refused create and update' do
      # The update case needs the dump Hosts#update reads before it decides; the three creates go
      # straight out.
      dump_first = [Fixtures.exchange('hosts/crud', 'host.get', 3)]
      [
        [[Fixtures.exchange('hosts/crud', 'host.create', 1)], /cannot be empty/, ->(wrapper) { wrapper.create(host: name) }],
        [[Fixtures.exchange('hosts/crud', 'host.create', 2)], /Wrong fields for host/, ->(wrapper) { wrapper.create(groups: [{ groupid: group }]) }],
        [[Fixtures.exchange('hosts/crud', 'host.create', 3)], /Incorrect arguments passed to function/, ->(wrapper) { wrapper.create(host: name, groups: [{ groupid: group }], interfaces: [{ type: 1, main: 1, useip: 1, ip: '192.0.2.10', port: '10050' }]) }],
        [dump_first + [Fixtures.exchange('hosts/crud', 'host.update', 3)], /unexpected parameter .automatic./, ->(wrapper) { wrapper.update(hostid: id, tags: [{ tag: 'zbxapi-spec', value: 'hosts', automatic: 1 }]) }]
      ].each do |exchanges, reason, call|
        refused = described_class.new(FakeClient.new(exchanges))
        expect { call.call(refused) }.to raise_error(ZabbixApi::ApiError) { |error| expect(error.error_message).to match(reason) }
      end
    end
  end
end
