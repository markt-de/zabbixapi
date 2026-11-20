# Contract: ZabbixApi::Drules
#   evidence: spec/fixtures/drules/crud.json;
#             https://www.zabbix.com/documentation/7.0/en/manual/api/reference/drule,
#             https://www.zabbix.com/documentation/7.0/en/manual/api/reference/dcheck
#   classes:  hooks, and the five default_options | create wraps one object and merges those
#             defaults, the caller's status beating the arming 0 | the nil placeholders are dropped
#             from the request rather than sent as JSON null | the four reads and the request each
#             builds | get_id filters on the whole payload | all maps the name to an Integer id |
#             update skips an equal scalar, issues a differing one, honours force, always issues for
#             dchecks because output extend never returns them, refuses without an id | the four
#             upsert branches, the id merged in as a String | the three aliases | delete sends a
#             bare id and returns an Integer whether the answer holds an Integer or a String | key
#             normalisation, four entry points, four mechanisms | refusals: a duplicate name, a rule
#             without checks, the read-only error, an id no rule carries
#   not here: the iprange formats, the delay range, the concurrency_max bounds, the status enum and
#             the sixteen dcheck types - server validation of values the wrapper only forwards, one
#             representative of each kept in the acceptance spec; a rule created enabled, by status
#             0 or by the server's own status default, and the action-condition restrictions on
#             update and delete, reproduced nowhere in this suite; dcheck.get, which the gem does
#             not wrap; bulk arrays, which Basic#create and #delete handle and Basic's own spec
#             covers; get_id's refusal on more than one match, unreachable here because drule names
#             are unique server-wide
require 'spec_helper'

RSpec.describe ZabbixApi::Drules do
  crud = Fixtures.exchanges('drules/crud')
  row = Fixtures.exchange('drules/crud', 'drule.get')['result'].first
  table = Fixtures.exchange('drules/crud', 'drule.get', 6)['result']
  id = row['druleid'].to_i
  name = row['name']
  # Spelled out rather than taken from Drules#default_options, so a changed default fails here.
  defaults = { name: nil, iprange: nil, delay: '3600', status: 0, concurrency_max: 0 }
  # A TCP check, and a Zabbix agent check with the key_ its type requires.
  tcp_check = { type: 8, ports: '65001' }
  agent_check = { type: 9, key_: 'system.uname', ports: '10050' }

  let(:client) { FakeClient.new(crud) }
  let(:drules) { described_class.new(client) }

  it_behaves_like 'a Basic resource', method_name: 'drule', identify: 'name', key: 'druleid', keys: 'druleids', default_options: { name: nil, iprange: nil, delay: '3600', status: 0, concurrency_max: 0 }

  it_behaves_like 'an inherited create', payload: { name: name, iprange: '192.0.2.10', status: 1, dchecks: [tcp_check] }, defaults: defaults, exchange: Fixtures.exchange('drules/crud', 'drule.create')
  it_behaves_like 'an inherited delete', id: Fixtures.exchange('drules/crud', 'drule.delete')['params'].first, exchange: Fixtures.exchange('drules/crud', 'drule.delete')
  it_behaves_like 'an inherited get_id', identify: 'name', key: 'druleid', value: name, rows: Fixtures.exchange('drules/crud', 'drule.get', 1)['result']
  it_behaves_like 'an inherited all', identify: 'name', key: 'druleid', rows: table
  it_behaves_like 'the inherited reads', identify: 'name', key: 'druleid', value: name, id: id, rows: [row]
  # collection: dchecks, the one collection drule.create and drule.update take, which output: extend
  # never returns, so a payload naming it is never skipped.
  it_behaves_like 'an update that skips when unchanged', key: 'druleid', id: id, dump: [row], unchanged: { delay: row['delay'] }, changed: { delay: '2h' }, collection: { dchecks: [agent_check] }
  it_behaves_like 'the aliases', exchanges: crud, payload: { name: name }, id: id

  it_behaves_like 'a lookup that refuses to run blind', method: :dump_by_id, field: 'druleid'
  it_behaves_like 'a lookup that refuses to run blind', method: :get_id, field: 'name'

  # One instance per normalisation mechanism rather than per entry point: the merge against
  # default_options in create, the conditional symbolisation in get_id, require_field! in
  # dump_by_id, and the dump comparison in update.
  it_behaves_like 'a key-normalising entry point', method: :create, payload: { name: name, iprange: '192.0.2.10', status: 1, dchecks: [tcp_check] }, exchanges: crud
  it_behaves_like 'a key-normalising entry point', method: :get_id, payload: { name: name }, exchanges: crud
  it_behaves_like 'a key-normalising entry point', method: :dump_by_id, payload: { druleid: id }, exchanges: crud
  it_behaves_like 'a key-normalising entry point', method: :update, payload: { druleid: id, delay: '2h' }, exchanges: crud

  describe '#create' do
    it 'sends status 0, enabled, with delay 3600 and concurrency_max 0 when the caller passes none of the three' do
      armed = FakeClient.new([Fixtures.exchange('drules/crud', 'drule.create')])

      described_class.new(armed).create(name: name, iprange: '192.0.2.10', dchecks: [tcp_check])
      expect(armed.sent('drule.create').last.first).to include('status' => 0, 'delay' => '3600', 'concurrency_max' => 0)
    end

    it 'omits the iprange placeholder the caller did not supply' do
      # The replayed answer is an accepted create's, standing in for the id only: the server refuses
      # a create without iprange, which the acceptance spec asserts.
      accepted = Fixtures.exchange('drules/crud', 'drule.create')
      fake = FakeClient.new([accepted])

      expect(described_class.new(fake).create(name: name, status: 1, dchecks: [tcp_check])).to eq(accepted['result']['druleids'].first.to_i)
      expect(fake.sent('drule.create').last.first).not_to have_key('iprange')
    end

    it 'omits the name placeholder the caller did not supply, rather than sending JSON null' do
      # The replayed exchange is this very request, refused with `Field "name" is mandatory.`, the
      # message the acceptance spec asserts.
      fake = FakeClient.new([Fixtures.exchange('drules/crud', 'drule.create', 2)])

      expect { described_class.new(fake).create(iprange: '192.0.2.12', status: 1, dchecks: [tcp_check]) }.to raise_error(ZabbixApi::ApiError)
      expect(fake.sent('drule.create').last.first).not_to have_key('name')
    end

    it 'cannot supply the required dchecks from any default, and the server says so' do
      fake = FakeClient.new([Fixtures.exchange('drules/crud', 'drule.create', 4)])

      expect { described_class.new(fake).create(name: name, iprange: '192.0.2.13', status: 1) }
        .to raise_error(ZabbixApi::ApiError) { |error| expect(error.error_message).to match(/without checks/) }
      expect(fake.sent('drule.create').last.first).not_to have_key('dchecks')
    end

    it "reaches the caller as an ApiError whose error_message joins the server's message and data, for a duplicate name" do
      fake = FakeClient.new([Fixtures.exchange('drules/crud', 'drule.create', 1)])

      expect { described_class.new(fake).create(name: name, iprange: '192.0.2.11', status: 1, dchecks: [tcp_check]) }
        .to raise_error(ZabbixApi::ApiError) { |error| expect(error.error_message).to match(/\AInvalid params\.: Discovery rule .* already exists\.\z/) }
    end
  end

  describe '#update' do
    it 'issues the call for a payload naming dchecks, which the dump it compares against lacks' do
      dump = Fixtures.exchange('drules/crud', 'drule.get', 9)
      fake = FakeClient.new([dump, Fixtures.exchange('drules/crud', 'drule.update', 1)])

      expect(dump['result'].first).not_to have_key('dchecks')
      expect(described_class.new(fake).update(druleid: id, dchecks: [agent_check])).to eq(id)
      expect(fake.sent('drule.update')).to eq([[{ 'druleid' => id, 'dchecks' => [{ 'type' => 9, 'key_' => 'system.uname', 'ports' => '10050' }] }]])
    end

    it 'raises before any request when the payload carries no druleid, naming the guard it came from' do
      expect { drules.update(delay: '2h') }.to raise_error(ZabbixApi::ApiError, /druleid not supplied in call to dump_by_id/)
      expect(client.calls).to be_empty
    end

    it 'reaches the caller with the refusal of the second request, the dump before it having succeeded' do
      fake = FakeClient.new([Fixtures.exchange('drules/crud', 'drule.get', 10), Fixtures.exchange('drules/crud', 'drule.update', 2)])

      expect { described_class.new(fake).update({ druleid: id, error: 'boom' }, true) }
        .to raise_error(ZabbixApi::ApiError) { |error| expect(error.error_message).to match(/Incorrect arguments passed to function/) }
      expect(fake.count('drule.get')).to eq(1)
    end
  end

  describe '#create_or_update' do
    it 'looks the name up, dumps the rule and updates it with the id merged in as a String' do
      found = Fixtures.exchange('drules/crud', 'drule.get', 11)
      fake = FakeClient.new([found, Fixtures.exchange('drules/crud', 'drule.get', 12), Fixtures.exchange('drules/crud', 'drule.update', 3)])

      expect(described_class.new(fake).create_or_update(name: name, iprange: '192.0.2.10', status: 1, delay: '30m', dchecks: [tcp_check])).to eq(id)
      expect(fake.sent('drule.get')).to eq([{ 'filter' => { 'name' => name }, 'output' => %w[druleid name] },
                                            { 'filter' => { 'druleid' => id.to_s }, 'output' => 'extend' }])
      expect(fake.sent('drule.update').first.first['druleid']).to eq(id.to_s)
    end

    it 'creates the payload under the defaults when the name exists nowhere, and issues no update' do
      created = Fixtures.exchange('drules/crud', 'drule.create', 8)
      fake = FakeClient.new([Fixtures.exchange('drules/crud', 'drule.get', 13), created])
      unseen = "#{name}-unseen"

      expect(described_class.new(fake).create_or_update(name: unseen, iprange: '192.0.2.16', status: 1, dchecks: [tcp_check])).to eq(created['result']['druleids'].first.to_i)
      expect(fake.sent('drule.create')).to eq([[{ 'name' => unseen, 'iprange' => '192.0.2.16', 'delay' => '3600', 'status' => 1, 'concurrency_max' => 0, 'dchecks' => [{ 'type' => 8, 'ports' => '65001' }] }]])
      expect(fake.count('drule.update')).to eq(0)
    end
  end

  describe '#get_or_create' do
    it 'returns the id the lookup found and creates nothing' do
      found = Fixtures.exchange('drules/crud', 'drule.get', 14)
      target = found['result'].first
      fake = FakeClient.new([found])

      expect(described_class.new(fake).get_or_create(name: target['name'], iprange: '192.0.2.16', status: 1, dchecks: [tcp_check])).to eq(target['druleid'].to_i)
      expect(fake.count('drule.create')).to eq(0)
    end

    it 'creates when the lookup finds nothing, filtering on the name alone and returning the new id' do
      created = Fixtures.exchange('drules/crud', 'drule.create', 9)
      fake = FakeClient.new([Fixtures.exchange('drules/crud', 'drule.get', 15), created])
      unseen = "#{name}-unknown"

      expect(described_class.new(fake).get_or_create(name: unseen, iprange: '192.0.2.17', status: 1, dchecks: [tcp_check])).to eq(created['result']['druleids'].first.to_i)
      expect(fake.sent('drule.get')).to eq([{ 'filter' => { 'name' => unseen }, 'output' => %w[druleid name] }])
      expect(fake.count('drule.create')).to eq(1)
    end
  end

  describe '#get_raw' do
    it 'passes countOutput through and hands the String count back unconverted' do
      counted = FakeClient.new([Fixtures.exchange('drules/crud', 'drule.get', 5)])

      expect(described_class.new(counted).get_raw(countOutput: true, druleids: [id])).to eq('1')
      expect(counted.sent('drule.get')).to eq([{ 'countOutput' => true, 'druleids' => [id] }])
    end

    it 'passes selectDChecks through and returns the checks it selects' do
      selected = Fixtures.exchange('drules/crud', 'drule.get', 4)
      fake = FakeClient.new([selected])

      returned = described_class.new(fake).get_raw(output: %w[druleid name], druleids: [selected['result'].first['druleid'].to_i], selectDChecks: 'extend')
      expect(returned.first['dchecks'].map { |check| check['type'] }).to eq(%w[8 9])
      expect(fake.sent('drule.get').first['selectDChecks']).to eq('extend')
    end
  end

  describe '#delete' do
    it 'sends a bare id inside an Array and returns an Integer when the answer holds a String, the other recorded answer holding an Integer' do
      numeric = Fixtures.exchange('drules/crud', 'drule.delete')
      string = Fixtures.exchange('drules/crud', 'drule.delete', 1)
      # drule.delete echoes the type it was given, so parse_keys' to_i has an Integer and a String
      # to convert.
      expect([numeric['result']['druleids'].first, string['result']['druleids'].first]).to match([an_instance_of(Integer), an_instance_of(String)])

      by_string = FakeClient.new([string])
      expect(described_class.new(by_string).delete(string['params'].first)).to eq(string['params'].first.to_i)
      expect(by_string.sent('drule.delete')).to eq([[string['params'].first]])
    end

    it 'raises the refusal for an id no rule carries' do
      fake = FakeClient.new([Fixtures.exchange('drules/crud', 'drule.delete', 2)])

      expect { described_class.new(fake).delete(999999999) }
        .to raise_error(ZabbixApi::ApiError) { |error| expect(error.error_message).to match(/No permissions to referred object or it does not exist/) }
    end
  end
end
