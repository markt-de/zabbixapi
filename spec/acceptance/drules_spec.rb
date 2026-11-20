# Contract: ZabbixApi::Drules live
#   evidence: https://www.zabbix.com/documentation/7.0/en/manual/api/reference/drule,
#             https://www.zabbix.com/documentation/7.0/en/manual/api/reference/dcheck
#   classes:  create stores the gem's forced delay and concurrency_max verbatim | the documented
#             parameter set, the standing proxy and two checks read back field by field | a
#             string-keyed payload reaches the server | iprange, delay and concurrency_max, one
#             accepted and one refused value each | refusals: duplicate name, a name the caller
#             omitted, a rule without checks, an agent check without key_, uniq on a check that may
#             not carry it, status outside the enum, an empty iprange and an omitted one | reads by
#             name, by id and the whole table, the two blind-lookup guards, get_raw with
#             selectDChecks in both forms, the one read of the class that returns a rule's checks |
#             update writes a scalar, replaces dchecks with new ids, leaves the rule as it was when
#             nothing differs, error aside, returns the id under force with the delay read back as
#             sent, refuses a rename onto a taken name and the read-only error | the four upsert
#             branches | the writing aliases | delete removes and refuses an id no rule carries |
#             aftercare
#   not here: the hooks and default_options, and the request create builds from them, which the unit
#             spec asserts offline; that an unchanged update sends no request, visible only in the
#             traffic and asserted offline; a rule created enabled, by status 0 or by the server's
#             own status default, and the action-condition restrictions on update and delete -
#             nothing here is ever enabled, and the restrictions need an action this spec does not
#             create; the other fourteen dcheck types, the further iprange formats, masks and
#             whitespace forms, the refusals of a malformed delay and the host_source and
#             name_source enums, all server validation of values the wrapper only forwards, one
#             representative of each kind kept; the count of discovered hosts and services, a
#             server-wide figure any enabled discovery rule on the server can move
require 'spec_helper'

RSpec.describe 'ZabbixApi::Drules live', type: :acceptance do
  klass = 'drules'

  # Every rule this spec creates is disabled. An enabled rule starts discovering as soon as it is
  # added, as the manual's Configuring a network discovery rule page states, and delay governs only
  # the repeats, so status is the only lever - and the gem's own default_options would arm it with
  # 0. A payload overrides this only to prove the enum refusal, and no payload here ever passes
  # status 0.
  def disabled(payload)
    { status: 1 }.merge(payload)
  end

  # A TCP check on port 65001, enough to satisfy the required dchecks. Every address below is RFC
  # 5737, RFC 3849 or RFC 2544 space, reserved for documentation and benchmarking, but for the /8
  # mask the server refuses as too wide.
  def tcp_check(extra = {})
    { type: 8, ports: '65001' }.merge(extra)
  end

  # A Zabbix agent check, one of the four types the dcheck object reference requires a key_ for.
  def agent_check(extra = {})
    { type: 9, key_: 'system.uname', ports: '10050' }.merge(extra)
  end

  def checks_of(druleid)
    Live.one('drule', druleids: [druleid], selectDChecks: 'extend')['dchecks'].sort_by { |check| check['dcheckid'].to_i }
  end

  before(:all) do
    Live.preclean(klass, 'drule')
    @proxyid = Live.one('proxy', filter: { name: Live::PROXY_NAME })['proxyid'].to_i
    @one = Live.owns('drule', Live.retrying('create one') { Live.session.drules.create(disabled(name: Live.name(klass, 'one'), iprange: '192.0.2.10', dchecks: [tcp_check])) })
    @full = Live.owns('drule', Live.retrying('create full') do
      Live.session.drules.create(disabled(name: Live.name(klass, 'full'), iprange: '192.0.2.1-100, 198.51.100.0/24',
                                          delay: '2h', concurrency_max: 7, proxyid: @proxyid,
                                          dchecks: [tcp_check, agent_check(uniq: 1, host_source: 3)]))
    end)
  end

  after(:all) do
    Live.teardown
    # Nothing registers a rule a refusal example did not expect to be created, so sweep the prefix
    # once more; the aftercare example asserts that nothing is left to sweep.
    Live.preclean(klass, 'drule')
  end

  let(:drules) { Live.session.drules }

  describe 'create' do
    it 'stores the rule disabled, carrying the delay and concurrency_max that default_options forced, both verbatim' do
      stored = Live.one('drule', druleids: [@one])
      expect(stored.values_at('name', 'iprange', 'status')).to eq([Live.name(klass, 'one'), '192.0.2.10', '1'])
      # The drule object reference documents the server default as 1h; what the gem sends is stored
      # as sent.
      expect(stored.values_at('delay', 'concurrency_max', 'proxyid', 'error')).to eq(['3600', '0', '0', ''])
    end

    it 'stores the documented parameter set of one call, the proxy among it and both checks under the rule' do
      stored = Live.one('drule', druleids: [@full], selectDChecks: 'extend')
      expect(stored.values_at('iprange', 'delay', 'concurrency_max', 'proxyid')).to eq(['192.0.2.1-100, 198.51.100.0/24', '2h', '7', @proxyid.to_s])
      agent = stored['dchecks'].find { |check| check['type'] == '9' }
      expect(stored['dchecks'].map { |check| check['type'] }.sort).to eq(%w[8 9])
      expect(agent.values_at('key_', 'ports', 'uniq', 'host_source')).to eq(['system.uname', '10050', '1', '3'])
      expect(stored['dchecks'].map { |check| check['druleid'] }.uniq).to eq([@full.to_s])
    end

    it 'accepts a string-keyed payload and the server stores the same rule' do
      rule = Live.owns('drule', Live.retrying('create strings') { drules.create('name' => Live.name(klass, 'strings'), 'iprange' => '192.0.2.20', 'status' => 1, 'dchecks' => [{ 'type' => 8, 'ports' => '65001' }]) })
      expect(Live.one('drule', druleids: [rule]).values_at('name', 'iprange', 'status')).to eq([Live.name(klass, 'strings'), '192.0.2.20', '1'])
    end

    it 'refuses a name another rule already carries' do
      expect { Live.retrying('create duplicate') { drules.create(disabled(name: Live.name(klass, 'one'), iprange: '192.0.2.21', dchecks: [tcp_check])) } }
        .to raise_error(ZabbixApi::ApiError, /already exists/)
    end

    it 'refuses a name the caller omitted' do
      expect { Live.retrying('create nameless') { drules.create(disabled(iprange: '192.0.2.22', dchecks: [tcp_check])) } }
        .to raise_error(ZabbixApi::ApiError, /Field .*name.* is mandatory/)
    end

    it 'refuses an explicit empty iprange' do
      expect { Live.retrying('create empty iprange') { drules.create(disabled(name: Live.name(klass, 'emptyip'), iprange: '', dchecks: [tcp_check])) } }
        .to raise_error(ZabbixApi::ApiError, /field .*iprange.*: cannot be empty/)
    end

    # The drule object reference marks iprange required for create. Basic#merge_defaults leaves out
    # an iprange the caller did not set, and the server refuses that omission as it refuses ''; a
    # create carrying iprange null, which the gem sends only where the caller set it to nil, is
    # accepted and stores ''.
    it 'refuses an omitted iprange as it refuses an explicit empty one' do
      expect { Live.retrying('create noiprange') { drules.create(disabled(name: Live.name(klass, 'noiprange'), dchecks: [tcp_check])) } }
        .to raise_error(ZabbixApi::ApiError, /field .*iprange.*: cannot be empty/)
    end

    it 'refuses a rule with no checks' do
      expect { Live.retrying('create checkless') { drules.create(disabled(name: Live.name(klass, 'nochecks'), iprange: '192.0.2.23')) } }
        .to raise_error(ZabbixApi::ApiError, /without checks/)
    end

    it 'refuses a Zabbix agent check that carries no key_' do
      expect { Live.retrying('create keyless check') { drules.create(disabled(name: Live.name(klass, 'nokey'), iprange: '192.0.2.24', dchecks: [{ type: 9, ports: '10050' }])) } }
        .to raise_error(ZabbixApi::ApiError, /key_.*is mandatory/)
    end

    it 'refuses uniq on a TCP check, which the dcheck object reference supports on the agent and SNMP types only' do
      expect { Live.retrying('create uniq tcp') { drules.create(disabled(name: Live.name(klass, 'uniqtcp'), iprange: '192.0.2.25', dchecks: [tcp_check(uniq: 1)])) } }
        .to raise_error(ZabbixApi::ApiError, /can be made unique/)
    end

    # drule.create words the three value refusals below two ways: status 2 draws
    # `Incorrect value "2" for "status" field.` and concurrency_max 1000
    # `Incorrect value "1000" for "concurrency_max" field.`, while delay 604801 draws
    # `Incorrect value for field "delay": value must be one of 1-604800.`
    it 'refuses a status one step outside the documented enum' do
      expect { Live.retrying('create status 2') { drules.create(name: Live.name(klass, 'status2'), iprange: '192.0.2.26', status: 2, dchecks: [tcp_check]) } }
        .to raise_error(ZabbixApi::ApiError, /Incorrect value .*for .*status.* field/)
    end

    it 'stores a comma list of the documented iprange forms verbatim, whitespace and all' do
      range = '192.0.2.1-100, 198.51.100.0/24, 203.0.113.7, 2001:db8::/112'
      rule = Live.owns('drule', Live.retrying('create ranges') { drules.create(disabled(name: Live.name(klass, 'ranges'), iprange: range, dchecks: [tcp_check])) })
      expect(Live.one('drule', druleids: [rule])['iprange']).to eq(range)
    end

    it "refuses a mask that exceeds the 65536-address limit, which the manual's Configuring a network discovery rule page gives as less than 64K" do
      expect { Live.retrying('create wide mask') { drules.create(disabled(name: Live.name(klass, 'widemask'), iprange: '198.18.0.0/8', dchecks: [tcp_check])) } }
        .to raise_error(ZabbixApi::ApiError, /exceeds .*65536.* address limit/)
    end

    it 'stores a delay of 604800 seconds, one week, where the drule object reference documents no bound' do
      rule = Live.owns('drule', Live.retrying('create ceiling delay') { drules.create(disabled(name: Live.name(klass, 'ceiling'), iprange: '192.0.2.27', delay: '604800', dchecks: [tcp_check])) })
      expect(Live.one('drule', druleids: [rule])['delay']).to eq('604800')
    end

    it 'refuses a delay of 604801 seconds, and the refusal names the range 1-604800' do
      expect { Live.retrying('create delay over') { drules.create(disabled(name: Live.name(klass, 'overdelay'), iprange: '192.0.2.28', delay: '604801', dchecks: [tcp_check])) } }
        .to raise_error(ZabbixApi::ApiError, /value must be one of 1-604800/)
    end

    it 'stores concurrency_max at its documented upper bound' do
      rule = Live.owns('drule', Live.retrying('create cc 999') { drules.create(disabled(name: Live.name(klass, 'cc999'), iprange: '192.0.2.29', concurrency_max: 999, dchecks: [tcp_check])) })
      expect(Live.one('drule', druleids: [rule])['concurrency_max']).to eq('999')
    end

    it 'refuses concurrency_max one past that bound' do
      expect { Live.retrying('create cc 1000') { drules.create(disabled(name: Live.name(klass, 'cc1000'), iprange: '192.0.2.30', concurrency_max: 1000, dchecks: [tcp_check])) } }
        .to raise_error(ZabbixApi::ApiError, /Incorrect value .*for .*concurrency_max.* field/)
    end
  end

  describe 'reads' do
    it 'get_id returns the id stored under that name' do
      expect(Live.retrying('get_id') { drules.get_id(name: Live.name(klass, 'one')) }).to eq(@one)
    end

    it 'get_id returns nil for a name no rule carries' do
      expect(Live.retrying('get_id absent') { drules.get_id(name: Live.name(klass, 'absent')) }).to be_nil
    end

    it 'get_id refuses to run blind' do
      expect { drules.get_id({}) }.to raise_error(ZabbixApi::ApiError, /name not supplied/)
    end

    it 'get_full_data returns the rule under its name with iprange, delay, concurrency_max, proxyid and error, and the checks are no part of it' do
      found = Live.retrying('get_full_data') { drules.get_full_data(name: Live.name(klass, 'one')) }
      expect(found.map { |rule| rule['druleid'].to_i }).to eq([@one])
      expect(found.first.keys).to include('iprange', 'delay', 'concurrency_max', 'proxyid', 'error')
      expect(found.first).not_to have_key('dchecks')
    end

    it 'dump_by_id finds the rule by its id' do
      expect(Live.retrying('dump_by_id') { drules.dump_by_id(druleid: @one) }.first['name']).to eq(Live.name(klass, 'one'))
    end

    it 'dump_by_id refuses to run blind' do
      expect { drules.dump_by_id({}) }.to raise_error(ZabbixApi::ApiError, /druleid not supplied/)
    end

    it 'all maps its own name to the id as an Integer and carries the stock rule Local network beside it' do
      table = Live.retrying('all') { drules.all }
      expect(table[Live.name(klass, 'one')]).to eq(@one)
      expect(table).to include('Local network')
    end

    it 'get_raw reaches the checks through selectDChecks' do
      row = Live.retrying('selectDChecks list') { drules.get_raw(output: %w[druleid name], druleids: [@full], selectDChecks: 'extend') }.first
      expect(row['dchecks'].map { |check| check['ports'] }.sort).to eq(%w[10050 65001])
    end

    it 'get_raw answers a String count instead of a list in the count form of that select' do
      row = Live.retrying('selectDChecks count') { drules.get_raw(druleids: [@full], selectDChecks: 'count') }.first
      expect(row['dchecks']).to eq('2')
    end
  end

  describe 'update' do
    it 'writes a scalar and the rule reads back changed' do
      rule = Live.owns('drule', Live.retrying('create updatable') { drules.create(disabled(name: Live.name(klass, 'updatable'), iprange: '192.0.2.31', dchecks: [tcp_check])) })
      expect(Live.retrying('update delay') { drules.update(druleid: rule, delay: '30m') }).to eq(rule)
      expect(Live.one('drule', druleids: [rule])['delay']).to eq('30m')
    end

    it 'replaces the checks rather than merging them, and the survivors carry ids the rule never had' do
      rule = Live.owns('drule', Live.retrying('create replaceable') { drules.create(disabled(name: Live.name(klass, 'replaceable'), iprange: '192.0.2.32', dchecks: [tcp_check, agent_check])) })
      before_ids = checks_of(rule).map { |check| check['dcheckid'].to_i }

      expect(Live.retrying('update dchecks') { drules.update(druleid: rule, dchecks: [tcp_check]) }).to eq(rule)
      after = checks_of(rule)
      expect(after.map { |check| check['type'] }).to eq(['8'])
      expect(after.map { |check| check['dcheckid'].to_i } & before_ids).to eq([])
    end

    it 'returns the id and leaves the rule as it was when nothing differs, error aside' do
      # error is read-only: the server writes it when executing the rule runs into a problem.
      before_state = Live.one('drule', druleids: [@full]).reject { |field, _| field == 'error' }
      expect(Live.retrying('update unchanged') { drules.update(druleid: @full, delay: '2h') }).to eq(@full)
      expect(Live.one('drule', druleids: [@full]).reject { |field, _| field == 'error' }).to eq(before_state)
    end

    it 'returns the id for a forced update, and the delay reads back as sent' do
      expect(Live.retrying('update forced') { drules.update({ druleid: @full, delay: '2h' }, true) }).to eq(@full)
      expect(Live.one('drule', druleids: [@full])['delay']).to eq('2h')
    end

    it 'raises when no druleid says which rule to write' do
      expect { drules.update(delay: '1h') }.to raise_error(ZabbixApi::ApiError, /druleid not supplied/)
    end

    it 'refuses a rename onto a name another rule carries, and the old name survives' do
      expect { Live.retrying('update duplicate name') { drules.update({ druleid: @one, name: Live.name(klass, 'full') }, true) } }
        .to raise_error(ZabbixApi::ApiError, /already exists/)
      expect(Live.one('drule', druleids: [@one])['name']).to eq(Live.name(klass, 'one'))
    end

    it 'refuses the read-only error property and leaves the stored value empty' do
      expect { Live.retrying('update error') { drules.update({ druleid: @one, error: 'boom' }, true) } }
        .to raise_error(ZabbixApi::ApiError, /Incorrect arguments passed to function/)
      expect(Live.one('drule', druleids: [@one])['error']).to eq('')
    end
  end

  describe 'upserts' do
    it 'create_or_update changes a property of an existing name without making a second rule' do
      expect(Live.retrying('upsert update') { drules.create_or_update(disabled(name: Live.name(klass, 'one'), iprange: '203.0.113.0/24', dchecks: [tcp_check])) }).to eq(@one)
      expect(Live.one('drule', druleids: [@one])['iprange']).to eq('203.0.113.0/24')
      expect(Live.count('drule', filter: { name: Live.name(klass, 'one') })).to eq(1)
    end

    it 'create_or_update creates when the name exists nowhere' do
      created = Live.owns('drule', Live.retrying('upsert create') { drules.create_or_update(disabled(name: Live.name(klass, 'upserted'), iprange: '192.0.2.33', dchecks: [tcp_check])) })
      expect(Live.one('drule', druleids: [created])['name']).to eq(Live.name(klass, 'upserted'))
    end

    it 'get_or_create returns the existing id and leaves one rule of that name' do
      expect(Live.retrying('get_or_create found') { drules.get_or_create(disabled(name: Live.name(klass, 'one'), iprange: '192.0.2.10', dchecks: [tcp_check])) }).to eq(@one)
      expect(Live.count('drule', filter: { name: Live.name(klass, 'one') })).to eq(1)
    end

    it 'get_or_create creates when the name exists nowhere' do
      created = Live.owns('drule', Live.retrying('get_or_create create') { drules.get_or_create(disabled(name: Live.name(klass, 'gotten'), iprange: '192.0.2.34', dchecks: [tcp_check])) })
      expect(Live.one('drule', druleids: [created])['name']).to eq(Live.name(klass, 'gotten'))
    end
  end

  describe 'aliases' do
    it 'add creates the rule under the name it was given' do
      added = Live.owns('drule', Live.retrying('add') { drules.add(disabled(name: Live.name(klass, 'added'), iprange: '192.0.2.35', dchecks: [tcp_check])) })
      expect(Live.one('drule', druleids: [added])['name']).to eq(Live.name(klass, 'added'))
    end

    it 'destroy removes the rule and returns its id' do
      doomed = Live.owns('drule', Live.retrying('create doomed') { drules.create(disabled(name: Live.name(klass, 'doomed'), iprange: '192.0.2.36', dchecks: [tcp_check])) })
      expect(Live.retrying('destroy') { drules.destroy(doomed) }).to eq(doomed)
      Live.disown('drule', doomed)
      expect(Live.get('drule', druleids: [doomed])).to eq([])
    end
  end

  describe 'delete' do
    it 'removes the rule with its checks and returns its id' do
      disposable = Live.owns('drule', Live.retrying('create disposable') { drules.create(disabled(name: Live.name(klass, 'disposable'), iprange: '192.0.2.37', dchecks: [tcp_check])) })
      checkid = checks_of(disposable).first['dcheckid'].to_i

      expect(Live.retrying('delete') { drules.delete(disposable) }).to eq(disposable)
      Live.disown('drule', disposable)
      expect(Live.get('drule', druleids: [disposable])).to eq([])
      expect(Live.get('dcheck', dcheckids: [checkid])).to eq([])
    end

    it 'refuses an id no rule carries' do
      expect { Live.retrying('delete unknown') { drules.delete(999999999) } }
        .to raise_error(ZabbixApi::ApiError, /No permissions to referred object or it does not exist/)
    end
  end

  describe 'aftercare' do
    it 'leaves no discovery rule under its prefix once torn down, and the standing hosts and proxy and the stock rule Local network still present' do
      Live.teardown
      expect(Live.get('drule', search: { name: Live.prefix(klass) })).to eq([])
      expect(Live.get('host', filter: { host: Live::AGENT_HOSTS }).map { |host| host['host'] }).to match_array(Live::AGENT_HOSTS)
      expect(Live.one('proxy', filter: { name: Live::PROXY_NAME })['name']).to eq(Live::PROXY_NAME)
      expect(Live.one('drule', filter: { name: 'Local network' })['name']).to eq('Local network')
    end
  end
end
