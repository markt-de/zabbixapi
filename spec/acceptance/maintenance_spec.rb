# Contract: ZabbixApi::Maintenance live
#   evidence: https://www.zabbix.com/documentation/7.0/en/manual/api/reference/maintenance
#   classes:  a minimal create stores what was sent and the server's defaults | active_since and a
#             period duration are stored to the minute | one time period of each documented type |
#             problem tags and their operators | refusals: the five requirements, a duplicate name,
#             active_till not after active_since, a caller-supplied maintenanceid | the enum holes
#             of tags_evaltype and timeperiod_type | the tag gate on maintenance_type | a gated
#             time-period property outside its condition, even at its default | a conditional
#             sub-field | the period bounds | reads by name, by id, the whole table, the four
#             selects and the deprecated one, groupids | update writes a scalar, replaces every
#             collection, leaves an unchanged object alone with and without force, and is refused
#             when neither groups nor hosts would be left | the deprecated groupids still attach |
#             the four upsert branches | the writing aliases | delete, an unknown id, and the host
#             group a maintenance holds | aftercare
#   not here: the hooks and the wire shapes of the reads, which belong to the unit spec, as do the
#             two local guards of dump_by_id and get_id, which raise before any request; the further
#             missing-parameter refusals (name, active_since, active_till) and the further
#             conditional sub-fields (monthly without month, monthly with neither day nor
#             dayofweek), each a second member of a class already represented; the tag operator hole
#             and the maintenance_type bounds, members of the enum class tags_evaltype represents;
#             whether a host actually enters maintenance, which depends on the server's one-minute
#             timer; the count form of a select, silently omitted on every maintenance select and
#             therefore nothing the gem can be held to
#
# Every call goes through Live.retrying, the refused ones included: the retry fires only on the
# errors Live::TRANSIENT matches, those reporting a lost or failed connection, and re-raises
# everything else at once, so a refusal still reaches its matcher while a dropped connection is
# retried rather than failing the example.
require 'spec_helper'

RSpec.describe 'ZabbixApi::Maintenance live', type: :acceptance do
  klass = 'maintenance'

  before(:all) do
    # Maintenances first: a host group that is the only group of a maintenance cannot be deleted.
    Live.preclean(klass, 'maintenance')
    Live.preclean(klass, 'host')
    Live.preclean(klass, 'hostgroup')
    @hg1 = Live.owns('hostgroup', Live.retrying('create hg1') { Live.session.hostgroups.create(name: Live.name(klass, 'hg1')) })
    @hg2 = Live.owns('hostgroup', Live.retrying('create hg2') { Live.session.hostgroups.create(name: Live.name(klass, 'hg2')) })
    @host = Live.owns('host', Live.retrying('create host') { Live.session.hosts.create(host: Live.name(klass, 'h1'), groups: [{ groupid: @hg1 }]) })
    # Minute-aligned from the start, because the server stores these to the minute anyway.
    @since = ((Time.now.to_i / 60) * 60) - 3600
    @till = @since + 86400
    @one = Live.owns('maintenance', Live.retrying('create one') { Live.session.maintenance.create(payload(Live.name(klass, 'one'))) })
    @rich = Live.owns('maintenance', Live.retrying('create rich') do
      Live.session.maintenance.create(payload(Live.name(klass, 'rich'),
                                              tags_evaltype: 2,
                                              hosts: [{ hostid: @host }],
                                              tags: [{ tag: 'service', operator: 0, value: 'mysqld' }, { tag: 'error', operator: 2, value: '' }],
                                              timeperiods: [period,
                                                            period(timeperiod_type: 2, start_time: 3600, every: 1),
                                                            period(timeperiod_type: 3, start_time: 3600, every: 1, dayofweek: 64),
                                                            period(timeperiod_type: 4, start_time: 3600, every: 1, dayofweek: 64, month: 1)]))
    end)
  end

  after(:all) { Live.teardown }

  let(:maintenance) { Live.session.maintenance }

  # One valid one-time period, so every probe varies exactly one thing.
  def period(extra = {})
    { timeperiod_type: 0, period: 3600 }.merge(extra)
  end

  # The five things create needs at once, as the maintenance object and maintenance.create
  # references require them: name, active_since, active_till, timeperiods and at least one of
  # groups/hosts. An empty timeperiods is refused as well.
  def payload(name, extra = {})
    { name: name, active_since: @since, active_till: @till, groups: [{ groupid: @hg1 }], timeperiods: [period] }.merge(extra)
  end

  def creating(part, extra = {})
    name = Live.name('maintenance', part)
    Live.owns('maintenance', Live.retrying("create #{part}") { Live.session.maintenance.create(payload(name, extra)) })
  end

  def refusing(part, extra = {})
    Live.retrying("refused #{part}") { Live.session.maintenance.create(payload(Live.name('maintenance', part), extra)) }
  end

  describe 'create' do
    it 'stores the five required properties, the two documented defaults and an empty description' do
      stored = Live.one('maintenance', maintenanceids: [@one], selectHostGroups: 'extend', selectTimeperiods: 'extend')
      expect(stored['name']).to eq(Live.name(klass, 'one'))
      expect([stored['active_since'].to_i, stored['active_till'].to_i]).to eq([@since, @till])
      expect([stored['maintenance_type'], stored['tags_evaltype'], stored['description']]).to eq(['0', '0', ''])
      expect(stored['hostgroups'].map { |group| group['groupid'].to_i }).to eq([@hg1])
      expect(stored['timeperiods'].map { |window| window['period'] }).to eq(['3600'])
    end

    it 'rounds active_since and a period duration down to the minute' do
      window = creating('trunc', active_since: @since + 37, timeperiods: [period(period: 3661)])
      stored = Live.one('maintenance', maintenanceids: [window], selectTimeperiods: 'extend')
      expect(stored['active_since'].to_i).to eq(@since)
      expect(stored['timeperiods'].first['period']).to eq('3660')
    end

    it 'stores one time period of each documented type' do
      stored = Live.one('maintenance', maintenanceids: [@rich], selectTimeperiods: 'extend')
      expect(stored['timeperiods'].map { |window| window['timeperiod_type'] }.sort).to eq(%w[0 2 3 4])
      expect(stored['timeperiods'].map { |window| window['start_time'] }.sort).to eq(%w[0 3600 3600 3600])
    end

    it 'stores the problem tags with their operators' do
      stored = Live.one('maintenance', maintenanceids: [@rich], selectTags: 'extend')
      expect(stored['tags'].map { |tag| [tag['tag'], tag['operator'], tag['value']] }.sort).to eq([['error', '2', ''], ['service', '0', 'mysqld']])
    end

    it 'refuses a create that names neither groups nor hosts, and two empty arrays do not satisfy it' do
      expect { Live.retrying('refused nogroups') { maintenance.create(payload(Live.name(klass, 'nogroups')).except(:groups)) } }.to raise_error(ZabbixApi::ApiError, /At least one host group or host must be selected/)
      expect { refusing('empty', groups: [], hosts: []) }.to raise_error(ZabbixApi::ApiError, /At least one host group or host must be selected/)
    end

    it 'refuses a create without the required timeperiods' do
      expect { Live.retrying('refused notp') { maintenance.create(payload(Live.name(klass, 'notp')).except(:timeperiods)) } }.to raise_error(ZabbixApi::ApiError, /the parameter.*timeperiods.*is missing/)
    end

    it 'refuses a name another maintenance already carries' do
      expect { refusing('one') }.to raise_error(ZabbixApi::ApiError, /already exists/)
    end

    it 'refuses an active_till that does not exceed active_since, which the maintenance object reference does not document' do
      expect { refusing('samet', active_till: @since) }.to raise_error(ZabbixApi::ApiError, /cannot be less than or equal to the value of parameter/)
    end

    it 'refuses a caller-supplied maintenanceid' do
      expect { refusing('withid', maintenanceid: 99) }.to raise_error(ZabbixApi::ApiError, /unexpected parameter.*maintenanceid/)
    end
  end

  describe 'tags_evaltype and maintenance_type' do
    it 'stores tags_evaltype 2 and refuses the 1 the enumeration skips' do
      expect(Live.one('maintenance', maintenanceids: [@rich])['tags_evaltype']).to eq('2')
      expect { refusing('evalhole', tags_evaltype: 1) }.to raise_error(ZabbixApi::ApiError, /value must be one of 0, 2/)
    end

    it 'stores a maintenance without data collection and refuses tags on it, by rejecting the parameter' do
      window = creating('nodata', maintenance_type: 1)
      expect(Live.one('maintenance', maintenanceids: [window])['maintenance_type']).to eq('1')
      expect { refusing('notags', maintenance_type: 1, tags: [{ tag: 'x' }]) }.to raise_error(ZabbixApi::ApiError, /unexpected parameter.*tags/)
    end
  end

  describe 'time periods' do
    it 'refuses timeperiod_type 1, the hole in that enumeration' do
      expect { refusing('tphole', timeperiods: [period(timeperiod_type: 1)]) }.to raise_error(ZabbixApi::ApiError, /value must be one of 0, 2, 3, 4/)
    end

    it 'refuses start_time on a one-time-only period even at its documented default' do
      expect { refusing('sttot', timeperiods: [period(start_time: 3600)]) }.to raise_error(ZabbixApi::ApiError, /unexpected parameter.*start_time/)
      expect { refusing('sttot0', timeperiods: [period(start_time: 0)]) }.to raise_error(ZabbixApi::ApiError, /unexpected parameter.*start_time/)
    end

    it 'refuses a weekly period that names no dayofweek' do
      expect { refusing('nodow', timeperiods: [period(timeperiod_type: 3, start_time: 3600, every: 1)]) }.to raise_error(ZabbixApi::ApiError, /the parameter.*dayofweek.*is missing/)
    end

    it 'accepts both documented bounds of period and refuses one below' do
      window = creating('bounds', timeperiods: [period(period: 300), period(timeperiod_type: 2, start_time: 3600, every: 1, period: 86399940)])
      expect(Live.one('maintenance', maintenanceids: [window], selectTimeperiods: 'extend')['timeperiods'].map { |slot| slot['period'] }.sort).to eq(%w[300 86399940])
      expect { refusing('tooshort', timeperiods: [period(period: 240)]) }.to raise_error(ZabbixApi::ApiError, %r{/period})
    end
  end

  describe 'reads' do
    it 'get_id returns the id stored under that name' do
      expect(Live.retrying('get_id') { maintenance.get_id(name: Live.name(klass, 'one')) }).to eq(@one)
    end

    it 'get_id returns nil for a name no maintenance carries' do
      expect(Live.retrying('get_id absent') { maintenance.get_id(name: Live.name(klass, 'absent')) }).to be_nil
    end

    it 'get_full_data returns the maintenance under its name with active_since, active_till and tags_evaltype' do
      found = Live.retrying('get_full_data') { maintenance.get_full_data(name: Live.name(klass, 'one')) }
      expect(found.map { |window| window['maintenanceid'].to_i }).to eq([@one])
      expect(found.first).to include('active_since', 'active_till', 'tags_evaltype')
    end

    it 'dump_by_id finds the maintenance and carries none of the four collections' do
      dumped = Live.retrying('dump_by_id') { maintenance.dump_by_id(maintenanceid: @rich) }.first
      expect(dumped['name']).to eq(Live.name(klass, 'rich'))
      expect(dumped.keys).not_to include('hostgroups', 'hosts', 'tags', 'timeperiods')
    end

    it "all maps the name to the id, for both of this spec's fixture maintenances" do
      table = Live.retrying('all') { maintenance.all }
      expect(table[Live.name(klass, 'one')].to_i).to eq(@one)
      expect(table[Live.name(klass, 'rich')].to_i).to eq(@rich)
    end

    it 'get_raw passes the four documented selects through, and the deprecated selectGroups still answers' do
      row = Live.retrying('selects') { maintenance.get_raw(maintenanceids: [@rich], selectHostGroups: 'extend', selectHosts: 'extend', selectTags: 'extend', selectTimeperiods: 'extend') }.first
      expect(row.keys).to include('hostgroups', 'hosts', 'tags', 'timeperiods')
      expect(row['hosts'].map { |host| host['hostid'].to_i }).to eq([@host])
      deprecated = Live.retrying('selectGroups') { maintenance.get_raw(maintenanceids: [@rich], selectGroups: 'extend') }.first
      expect(deprecated['groups'].map { |group| group['groupid'].to_i }).to eq([@hg1])
    end

    it 'get_raw narrows by groupids and accepts sortfield with limit' do
      group = Live.owns('hostgroup', Live.retrying('create hgread') { Live.session.hostgroups.create(name: Live.name(klass, 'hgread')) })
      creating('scoped', groups: [{ groupid: group }])
      expect(Live.retrying('groupids') { maintenance.get_raw(groupids: [group], output: ['name']) }.map { |window| window['name'] }).to eq([Live.name(klass, 'scoped')])
      expect(Live.retrying('sortfield') { maintenance.get_raw(maintenanceids: [@one, @rich], output: ['maintenanceid'], sortfield: 'name', limit: 1) }.size).to eq(1)
    end
  end

  describe 'update' do
    it 'writes a scalar that reads back changed' do
      window = creating('scalar')
      expect(Live.retrying('update scalar') { maintenance.update(maintenanceid: window, description: 'erste') }).to eq(window)
      expect(Live.one('maintenance', maintenanceids: [window])['description']).to eq('erste')
    end

    it 'returns the id and leaves the object exactly as it was when nothing differs, forced or not' do
      before_state = Live.one('maintenance', maintenanceids: [@one])
      expect(Live.retrying('update unchanged') { maintenance.update(maintenanceid: @one, name: Live.name(klass, 'one')) }).to eq(@one)
      expect(Live.retrying('update forced') { maintenance.update({ maintenanceid: @one, name: Live.name(klass, 'one') }, true) }).to eq(@one)
      expect(Live.one('maintenance', maintenanceids: [@one])).to eq(before_state)
    end

    it 'replaces the host groups, and hosts can replace them entirely' do
      window = creating('replace')
      Live.retrying('update groups') { maintenance.update(maintenanceid: window, groups: [{ groupid: @hg2 }]) }
      expect(Live.one('maintenance', maintenanceids: [window], selectHostGroups: 'extend')['hostgroups'].map { |group| group['groupid'].to_i }).to eq([@hg2])
      Live.retrying('update hosts') { maintenance.update(maintenanceid: window, hosts: [{ hostid: @host }], groups: []) }
      stored = Live.one('maintenance', maintenanceids: [window], selectHostGroups: 'extend', selectHosts: 'extend')
      expect(stored['hosts'].map { |host| host['hostid'].to_i }).to eq([@host])
      expect(stored['hostgroups']).to eq([])
    end

    it 'replaces the time periods and the problem tags' do
      window = creating('collections', tags: [{ tag: 'first', operator: 0, value: 'x' }])
      Live.retrying('update collections') do
        maintenance.update(maintenanceid: window,
                           timeperiods: [period, period(timeperiod_type: 2, start_time: 7200, every: 1)],
                           tags: [{ tag: 'second', operator: 2, value: 'y' }])
      end
      stored = Live.one('maintenance', maintenanceids: [window], selectTimeperiods: 'extend', selectTags: 'extend')
      expect(stored['timeperiods'].map { |slot| slot['timeperiod_type'] }.sort).to eq(%w[0 2])
      expect(stored['tags'].map { |tag| tag['tag'] }).to eq(['second'])
    end

    it 'refuses an update that would leave neither host groups nor hosts, and the maintenance keeps its group' do
      expect { Live.retrying('refused empty update') { maintenance.update({ maintenanceid: @one, groups: [], hosts: [] }, true) } }.to raise_error(ZabbixApi::ApiError, /At least one host group or host must be selected/)
      expect(Live.one('maintenance', maintenanceids: [@one], selectHostGroups: 'extend')['hostgroups'].map { |group| group['groupid'].to_i }).to eq([@hg1])
    end
  end

  describe 'the deprecated parameters' do
    it 'attaches the host group given under the deprecated groupids' do
      name = Live.name(klass, 'deprecated')
      window = Live.owns('maintenance', Live.retrying('create deprecated') { maintenance.create(name: name, active_since: @since, active_till: @till, groupids: [@hg1], timeperiods: [period]) })
      expect(Live.one('maintenance', maintenanceids: [window], selectHostGroups: 'extend')['hostgroups'].map { |group| group['groupid'].to_i }).to eq([@hg1])
    end
  end

  describe 'upserts' do
    it 'create_or_update changes a property of an existing name without creating a second maintenance' do
      window = creating('upsert-target')
      expect(Live.retrying('upsert update') { maintenance.create_or_update(name: Live.name(klass, 'upsert-target'), description: 'per upsert') }).to eq(window)
      expect(Live.one('maintenance', maintenanceids: [window])['description']).to eq('per upsert')
      expect(Live.count('maintenance', filter: { name: Live.name(klass, 'upsert-target') })).to eq(1)
    end

    it 'create_or_update creates when the name is new' do
      created = Live.owns('maintenance', Live.retrying('upsert create') { maintenance.create_or_update(payload(Live.name(klass, 'upserted'))) })
      expect(Live.one('maintenance', maintenanceids: [created])['name']).to eq(Live.name(klass, 'upserted'))
    end

    it 'get_or_create returns the existing id and leaves one maintenance of that name' do
      expect(Live.retrying('get_or_create found') { maintenance.get_or_create(payload(Live.name(klass, 'one'))) }).to eq(@one)
      expect(Live.count('maintenance', filter: { name: Live.name(klass, 'one') })).to eq(1)
    end

    it 'get_or_create creates when the name is new' do
      created = Live.owns('maintenance', Live.retrying('get_or_create create') { maintenance.get_or_create(payload(Live.name(klass, 'gotten'))) })
      expect(Live.one('maintenance', maintenanceids: [created])['name']).to eq(Live.name(klass, 'gotten'))
    end
  end

  describe 'aliases' do
    it 'add creates the maintenance and destroy removes it' do
      added = Live.owns('maintenance', Live.retrying('add') { maintenance.add(payload(Live.name(klass, 'added'))) })
      expect(Live.one('maintenance', maintenanceids: [added])['name']).to eq(Live.name(klass, 'added'))
      expect(Live.retrying('destroy') { maintenance.destroy(added) }).to eq(added)
      Live.disown('maintenance', added)
      expect(Live.get('maintenance', maintenanceids: [added])).to eq([])
    end
  end

  describe 'delete' do
    it 'removes the maintenance and returns its id' do
      disposable = creating('disposable')
      expect(Live.retrying('delete') { maintenance.delete(disposable) }).to eq(disposable)
      Live.disown('maintenance', disposable)
      expect(Live.get('maintenance', maintenanceids: [disposable])).to eq([])
    end

    it 'refuses an id no maintenance carries' do
      expect { Live.retrying('refused delete') { maintenance.delete(999999999) } }.to raise_error(ZabbixApi::ApiError, /No permissions to referred object/)
    end

    it "refuses to delete a host group that is a maintenance's only group, which the hostgroup.delete reference does not list" do
      group = Live.owns('hostgroup', Live.retrying('create hg3') { Live.session.hostgroups.create(name: Live.name(klass, 'hg3')) })
      Live.owns('maintenance', Live.retrying('create onlygroup') { maintenance.create(payload(Live.name(klass, 'onlygroup'), groups: [{ groupid: group }])) })
      expect { Live.retrying('refused hostgroup delete') { Live.session.hostgroups.delete(group) } }.to raise_error(ZabbixApi::ApiError, /must contain at least one host or host group/)
      expect(Live.one('hostgroup', groupids: [group])['groupid'].to_i).to eq(group)
    end
  end

  describe 'aftercare' do
    it 'leaves no maintenance, host or host group under its prefix once torn down, and the standing hosts and proxy still present' do
      Live.teardown
      expect(Live.get('maintenance', search: { name: Live.prefix(klass) })).to eq([])
      expect(Live.get('hostgroup', search: { name: Live.prefix(klass) })).to eq([])
      expect(Live.get('host', search: { host: Live.prefix(klass) })).to eq([])
      expect(Live.get('host', filter: { host: Live::AGENT_HOSTS }).map { |host| host['host'] }).to match_array(Live::AGENT_HOSTS)
      expect(Live.one('proxy', filter: { name: Live::PROXY_NAME })['name']).to eq(Live::PROXY_NAME)
    end
  end
end
