# Contract: ZabbixApi::Actions live
#   evidence: https://www.zabbix.com/documentation/7.0/en/manual/api/reference/action
#   classes:  create stores name, event source and the disabled status this spec always sends | the
#             three trigger-only properties come back at their documented defaults | a discovery and
#             an internal action store their own event source | the operation is stored and readable
#             only through selectOperations | a string-keyed payload reaches the server | refusals:
#             duplicate name, missing name, no operation, read-only actionid, event source outside
#             the enum | the event-source gates, rejected as parameters rather than constrained, in
#             both directions, plus the undocumented esc_period range | eventsource is constant |
#             the filter: And/Or conditions stored with a generated eval_formula, a custom
#             expression whose eval_formula equals its formula, the two filter refusals |
#             operations: the recipient requirement, the per-source operation types, recovery and
#             update operations | reads: the override's four collections, the string-keyed call
#             narrowing too, get_id, dump_by_id, all, and three get_raw representatives | update
#             writes a scalar, leaves an unchanged object alone and accepts force | the filter and
#             the operations replace | the four upsert branches | the writing aliases | delete and
#             the refusal of an unknown id | aftercare
#   not here: the hooks and the reads' wire shapes, which the unit spec asserts offline, and the
#             update skip, which is visible only in the traffic; the documented status default and
#             status 0 itself, which need an *enabled* action - none is created here, an enabled
#             action acting on real events at once; event sources 2 and 4, which add no behaviour of
#             the gem beyond the three kept and refuse a property their source does not support as
#             an unexpected parameter, as discovery and internal actions do; the per-source
#             condition types and the remaining operation types, which are server behaviour; the
#             delete constraints an action's references put on the host groups, hosts, templates and
#             triggers they name, which belong to the classes whose objects they block; a status
#             *change*, which from the disabled state every action here is pinned to could only mean
#             enabling one - the no-op update below resends the 1 it already carries
require 'spec_helper'

RSpec.describe 'ZabbixApi::Actions live', type: :acceptance do
  # A method rather than a local, so the payload helpers below can name the class too.
  def klass
    'actions'
  end

  def stored(id, extra = {})
    Live.one('action', { actionids: [id] }.merge(extra))
  end

  # The four collections come back only when asked for by name; output: extend returns none.
  def stored_full(id)
    stored(id, selectOperations: 'extend', selectRecoveryOperations: 'extend', selectUpdateOperations: 'extend', selectFilter: 'extend')
  end

  def message_op
    { operationtype: 0, opmessage: { default_msg: 1, mediatypeid: @mediatype }, opmessage_grp: [{ usrgrpid: @usergroup }] }
  end

  def group_op
    { operationtype: 4, opgroup: [{ groupid: @group }] }
  end

  # Every action this spec creates carries status: 1. The API default is 0, enabled, and an enabled
  # action acts on real events at once, including events of objects other specs create.
  def trigger_payload(part, extra = {})
    { name: Live.name(klass, part), eventsource: 0, status: 1, esc_period: '1h', operations: [message_op] }.merge(extra)
  end

  def discovery_payload(part, extra = {})
    { name: Live.name(klass, part), eventsource: 1, status: 1, operations: [group_op] }.merge(extra)
  end

  def internal_payload(part, extra = {})
    { name: Live.name(klass, part), eventsource: 3, status: 1, esc_period: '1h', operations: [message_op] }.merge(extra)
  end

  def create_own(part, payload)
    Live.owns('action', Live.retrying("create #{part}") { Live.session.actions.create(payload) })
  end

  before(:all) do
    # Actions first: one that references a host group blocks that group's deletion.
    Live.preclean(klass, 'action')
    Live.preclean(klass, 'mediatype')
    Live.preclean(klass, 'hostgroup')
    @group = Live.owns('hostgroup', Live.retrying('hostgroup') { Live.session.hostgroups.get_or_create(name: Live.name(klass, 'hg')) })
    @mediatype = Live.owns('mediatype', Live.retrying('mediatype') { Live.session.mediatypes.get_or_create(name: Live.name(klass, 'mt'), type: 0, smtp_server: 'smtp.example.invalid', smtp_email: 'zbxapi-spec@example.invalid') })
    # A user group is no container the live layer may pre-clean by name, so it is upserted.
    @usergroup = Live.owns('usergroup', Live.retrying('usergroup') { Live.session.usergroups.get_or_create(name: Live.name(klass, 'ug')) })
    @trigger_action = create_own('one', trigger_payload('one'))
    @discovery_action = create_own('discovery', discovery_payload('discovery'))
    @internal_action = create_own('internal', internal_payload('internal'))
  end

  after(:all) { Live.teardown }

  let(:actions) { Live.session.actions }

  describe 'create' do
    it 'stores the name, the event source and the disabled status' do
      action = stored(@trigger_action)
      expect(action['name']).to eq(Live.name(klass, 'one'))
      expect([action['eventsource'], action['status']]).to eq(%w[0 1])
    end

    it 'leaves the three trigger-only properties at the defaults the action object reference documents for them' do
      action = stored(@trigger_action)
      expect([action['pause_symptoms'], action['pause_suppressed'], action['notify_if_canceled']]).to eq(%w[1 1 1])
    end

    it 'stores the event source of a discovery and of an internal action' do
      expect([stored(@discovery_action)['eventsource'], stored(@internal_action)['eventsource']]).to eq(%w[1 3])
    end

    it 'stores the operation, which selectOperations returns and output extend leaves out' do
      operations = stored_full(@trigger_action)['operations']
      expect(operations.map { |operation| operation['operationtype'] }).to eq(['0'])
      expect(operations.first['opmessage_grp'].map { |group| group['usrgrpid'].to_i }).to eq([@usergroup])
      expect(stored(@trigger_action)).not_to have_key('operations')
    end

    it 'accepts a string-keyed payload and the server sees the same name' do
      action = Live.owns('action', Live.retrying('create strings') do
        actions.create('name' => Live.name(klass, 'strings'), 'eventsource' => 0, 'status' => 1, 'esc_period' => '1h', 'operations' => [message_op])
      end)
      expect(stored(action)['name']).to eq(Live.name(klass, 'strings'))
    end

    it 'refuses a name another action already carries' do
      expect { Live.retrying('create duplicate') { actions.create(trigger_payload('one')) } }
        .to raise_error(ZabbixApi::ApiError, /already exists/)
    end

    it 'refuses a payload without a name' do
      expect { Live.retrying('create nameless') { actions.create(trigger_payload('nameless').except(:name)) } }
        .to raise_error(ZabbixApi::ApiError, /the parameter .*name.* is missing/)
    end

    it 'refuses an action that defines no operation at all' do
      expect { Live.retrying('create without operations') { actions.create(trigger_payload('noops').except(:operations)) } }
        .to raise_error(ZabbixApi::ApiError, /No operations defined for action/)
    end

    it 'refuses the read-only actionid' do
      expect { Live.retrying('create with an id') { actions.create(trigger_payload('withid', actionid: 99)) } }
        .to raise_error(ZabbixApi::ApiError, /unexpected parameter .*actionid/)
    end

    it 'refuses an event source outside the documented enum' do
      expect { Live.retrying('create bad eventsource') { actions.create(trigger_payload('badsource', eventsource: 5)) } }
        .to raise_error(ZabbixApi::ApiError, /value must be one of 0, 1, 2, 3, 4/)
    end
  end

  describe 'the properties gated on the event source' do
    it 'refuses esc_period on a discovery action, the parameter itself rather than its value' do
      expect { Live.retrying('discovery esc_period') { actions.create(discovery_payload('escdisc', esc_period: '1h')) } }
        .to raise_error(ZabbixApi::ApiError, /unexpected parameter .*esc_period/)
    end

    it 'refuses pause_suppressed on a discovery action even at the default 1 the action object reference gives it' do
      expect { Live.retrying('discovery pause_suppressed') { actions.create(discovery_payload('psdisc', pause_suppressed: 1)) } }
        .to raise_error(ZabbixApi::ApiError, /unexpected parameter .*pause_suppressed/)
    end

    it 'refuses notify_if_canceled on an internal action' do
      expect { Live.retrying('internal notify_if_canceled') { actions.create(internal_payload('nifc', notify_if_canceled: 1)) } }
        .to raise_error(ZabbixApi::ApiError, /unexpected parameter .*notify_if_canceled/)
    end

    it 'refuses recovery operations on a discovery action' do
      expect { Live.retrying('discovery recovery operations') { actions.create(discovery_payload('recdisc', recovery_operations: [{ operationtype: 11, opmessage: { default_msg: 1 } }])) } }
        .to raise_error(ZabbixApi::ApiError, /unexpected parameter .*recovery_operations/)
    end

    it 'refuses update operations on an internal action' do
      expect { Live.retrying('internal update operations') { actions.create(internal_payload('updint', update_operations: [{ operationtype: 12, opmessage: { default_msg: 1 } }])) } }
        .to raise_error(ZabbixApi::ApiError, /unexpected parameter .*update_operations/)
    end

    it 'refuses an esc_period below 60 s, naming a range the action object reference never states' do
      expect { Live.retrying('esc_period too small') { actions.create(trigger_payload('escmin', esc_period: '30s')) } }
        .to raise_error(ZabbixApi::ApiError, /value must be one of 60-604800/)
    end

    it 'accepts an esc_period of exactly 60 s and stores it verbatim' do
      action = create_own('esc60', trigger_payload('esc60', esc_period: '60s'))
      expect(stored(action)['esc_period']).to eq('60s')
    end
  end

  describe 'the event source is constant' do
    it 'refuses to change it on an existing action, which keeps the source it was created with' do
      expect { Live.retrying('change eventsource') { actions.update(actionid: @trigger_action, eventsource: 1) } }
        .to raise_error(ZabbixApi::ApiError, /Cannot update .*eventsource.* for action/)
      expect(stored(@trigger_action)['eventsource']).to eq('0')
    end
  end

  describe 'the filter' do
    it 'stores the conditions of an And/Or filter and generates an eval_formula' do
      conditions = [{ conditiontype: 0, operator: 0, value: @group.to_s }, { conditiontype: 3, operator: 2, value: Live.prefix(klass) }]
      action = create_own('andor', trigger_payload('andor', filter: { evaltype: 0, conditions: conditions }))
      filter = stored_full(action)['filter']
      expect(filter['evaltype']).to eq('0')
      expect(filter['conditions'].map { |condition| [condition['conditiontype'], condition['value']] })
        .to match_array([['0', @group.to_s], ['3', Live.prefix(klass)]])
      expect(filter['eval_formula']).not_to be_empty
    end

    it 'stores a custom expression and answers with an eval_formula equal to it, as the action object reference states' do
      conditions = [{ conditiontype: 0, operator: 0, value: @group.to_s, formulaid: 'A' },
                    { conditiontype: 3, operator: 2, value: Live.prefix(klass), formulaid: 'B' }]
      action = create_own('custom', trigger_payload('custom', filter: { evaltype: 3, formula: 'A or B', conditions: conditions }))
      filter = stored_full(action)['filter']
      expect([filter['formula'], filter['eval_formula']]).to eq(['A or B', 'A or B'])
      expect(filter['conditions'].length).to eq(2)
    end

    it 'refuses a custom expression that carries no formula' do
      conditions = [{ conditiontype: 0, operator: 0, value: @group.to_s, formulaid: 'A' }]
      expect { Live.retrying('custom without formula') { actions.create(trigger_payload('noformula', filter: { evaltype: 3, conditions: conditions })) } }
        .to raise_error(ZabbixApi::ApiError, /Invalid parameter .*formula/)
    end

    it 'refuses the read-only eval_formula' do
      conditions = [{ conditiontype: 0, operator: 0, value: @group.to_s }]
      expect { Live.retrying('supplied eval_formula') { actions.create(trigger_payload('evalf', filter: { evaltype: 0, conditions: conditions, eval_formula: 'A' })) } }
        .to raise_error(ZabbixApi::ApiError, /unexpected parameter .*eval_formula/)
    end
  end

  describe 'operations' do
    it 'refuses a send-message operation that names neither a user group nor a user' do
      lonely = { operationtype: 0, opmessage: { default_msg: 1, mediatypeid: @mediatype } }
      expect { Live.retrying('message without recipients') { actions.create(trigger_payload('nodest', operations: [lonely])) } }
        .to raise_error(ZabbixApi::ApiError, /No recipients specified for action operation message/)
    end

    it 'refuses an add-to-host-group operation on a trigger action, naming the property the type brings' do
      expect { Live.retrying('trigger operationtype 4') { actions.create(trigger_payload('optrig4', operations: [group_op])) } }
        .to raise_error(ZabbixApi::ApiError, /unexpected parameter .*opgroup/)
    end

    it 'accepts the add-host operation on a discovery action, and stores it' do
      action = create_own('dop2', discovery_payload('dop2', operations: [{ operationtype: 2 }]))
      expect(stored_full(action)['operations'].map { |operation| operation['operationtype'] }).to eq(['2'])
    end

    it 'stores recovery and update operations on a trigger action' do
      action = create_own('recupd', trigger_payload('recupd',
                                                    recovery_operations: [{ operationtype: 11, opmessage: { default_msg: 1 } }],
                                                    update_operations: [{ operationtype: 12, opmessage: { default_msg: 1 } }]))
      full = stored_full(action)
      expect(full['recovery_operations'].map { |operation| operation['operationtype'] }).to eq(['11'])
      expect(full['update_operations'].map { |operation| operation['operationtype'] }).to eq(['12'])
    end
  end

  describe 'reads' do
    it 'get_full_data returns the action with all four collections the override selects' do
      found = Live.retrying('get_full_data') { actions.get_full_data(name: Live.name(klass, 'one')) }
      expect(found.map { |action| action['actionid'].to_i }).to eq([@trigger_action])
      expect(found.first.keys).to include('operations', 'recovery_operations', 'update_operations', 'filter')
    end

    it 'get_full_data given a string key narrows to the one action' do
      found = Live.retrying('get_full_data string key') { actions.get_full_data('name' => Live.name(klass, 'one')) }
      expect(found.map { |action| action['actionid'].to_i }).to eq([@trigger_action])
      expect(found.map { |action| action['name'] }).not_to include(Live.name(klass, 'discovery'))
    end

    it 'get_id resolves the name to the id it was created under' do
      expect(Live.retrying('get_id') { actions.get_id(name: Live.name(klass, 'one')) }).to eq(@trigger_action)
    end

    it 'get_id returns nil for a name no action carries' do
      expect(Live.retrying('get_id absent') { actions.get_id(name: Live.name(klass, 'absent')) }).to be_nil
    end

    it 'get_id refuses to run blind' do
      expect { actions.get_id({}) }.to raise_error(ZabbixApi::ApiError, /name not supplied/)
    end

    it 'dump_by_id returns the action without any of the four collections' do
      dumped = Live.retrying('dump_by_id') { actions.dump_by_id(actionid: @trigger_action) }
      expect(dumped.map { |action| action['name'] }).to eq([Live.name(klass, 'one')])
      expect(dumped.first.keys).not_to include('operations', 'recovery_operations', 'update_operations', 'filter')
    end

    it 'dump_by_id refuses to run blind' do
      expect { actions.dump_by_id({}) }.to raise_error(ZabbixApi::ApiError, /actionid not supplied/)
    end

    it 'all maps its own name to the id as an Integer' do
      expect(Live.retrying('all') { actions.all }[Live.name(klass, 'one')]).to eq(@trigger_action)
    end

    it "get_raw narrows by usrgrpids to the actions messaging this spec's own user group" do
      names = Live.retrying('get_raw usrgrpids') { actions.get_raw(output: ['name'], usrgrpids: [@usergroup]) }.map { |action| action['name'] }
      expect(names).to include(Live.name(klass, 'one'))
      expect(names).not_to include(Live.name(klass, 'discovery'))
    end

    it 'get_raw sorts by the field it is given' do
      own = [@trigger_action, @discovery_action, @internal_action]
      names = Live.retrying('get_raw sortfield') { actions.get_raw(output: ['name'], actionids: own, sortfield: 'name') }.map { |action| action['name'] }
      expect(names).to eq(names.sort)
      expect(names.length).to eq(own.length)
    end

    it 'get_raw hands the countOutput String back unconverted, counted over the ids it was given' do
      expect(Live.retrying('get_raw countOutput') { actions.get_raw(countOutput: true, actionids: [@trigger_action, @discovery_action]) }).to eq('2')
    end
  end

  describe 'update' do
    it 'writes a scalar property and reads back changed' do
      action = create_own('scalar', trigger_payload('scalar'))
      expect(Live.retrying('update esc_period') { actions.update(actionid: action, esc_period: '2h') }).to eq(action)
      expect(stored(action)['esc_period']).to eq('2h')
    end

    it 'returns the id and leaves the action exactly as it was when nothing differs' do
      before_state = stored(@internal_action)
      expect(Live.retrying('update unchanged') { actions.update(actionid: @internal_action, status: 1) }).to eq(@internal_action)
      expect(stored(@internal_action)).to eq(before_state)
    end

    it 'returns the id for a forced update, and the esc_period reads back as sent' do
      expect(Live.retrying('update forced') { actions.update({ actionid: @internal_action, esc_period: '1h' }, true) }).to eq(@internal_action)
      expect(stored(@internal_action)['esc_period']).to eq('1h')
    end

    it 'raises when no actionid says which action to write' do
      expect { actions.update(name: Live.name(klass, 'one')) }.to raise_error(ZabbixApi::ApiError, /actionid not supplied/)
    end
  end

  describe 'the filter and the operations replace' do
    it 'a payload naming the filter replaces every stored condition' do
      conditions = [{ conditiontype: 0, operator: 0, value: @group.to_s }, { conditiontype: 3, operator: 2, value: Live.prefix(klass) }]
      action = create_own('refilter', trigger_payload('refilter', filter: { evaltype: 0, conditions: conditions }))
      Live.retrying('replace filter') { actions.update(actionid: action, filter: { evaltype: 0, conditions: [conditions.last] }) }
      filter = stored_full(action)['filter']
      expect(filter['conditions'].map { |condition| condition['conditiontype'] }).to eq(['3'])
    end

    it 'a payload naming operations replaces them, and two can coexist' do
      action = create_own('reops', trigger_payload('reops'))
      Live.retrying('replace operations') do
        actions.update(actionid: action, operations: [message_op, message_op.merge(esc_step_from: 2, esc_step_to: 2)])
      end
      steps = stored_full(action)['operations'].map { |operation| operation['esc_step_from'] }
      expect(steps).to match_array(%w[1 2])
    end

    it 'refuses to leave an action with no operation at all' do
      action = create_own('emptyops', trigger_payload('emptyops'))
      expect { Live.retrying('empty operations') { actions.update({ actionid: action, operations: [] }, true) } }
        .to raise_error(ZabbixApi::ApiError, /No operations defined for action/)
      expect(stored_full(action)['operations'].length).to eq(1)
    end
  end

  describe 'upserts' do
    it 'create_or_update changes a property of an existing name without making a second action' do
      expect(Live.retrying('upsert update') { actions.create_or_update(name: Live.name(klass, 'one'), esc_period: '3h') }).to eq(@trigger_action)
      expect(stored(@trigger_action)['esc_period']).to eq('3h')
      expect(Live.count('action', filter: { name: Live.name(klass, 'one') })).to eq(1)
    end

    it 'create_or_update creates when the name exists nowhere' do
      created = Live.owns('action', Live.retrying('upsert create') { actions.create_or_update(trigger_payload('upserted')) })
      expect(stored(created)['name']).to eq(Live.name(klass, 'upserted'))
    end

    it 'get_or_create returns the existing id and leaves one action of that name' do
      expect(Live.retrying('get_or_create found') { actions.get_or_create(trigger_payload('one')) }).to eq(@trigger_action)
      expect(Live.count('action', filter: { name: Live.name(klass, 'one') })).to eq(1)
    end

    it 'get_or_create creates when the name exists nowhere' do
      created = Live.owns('action', Live.retrying('get_or_create create') { actions.get_or_create(trigger_payload('gotten')) })
      expect(stored(created)['name']).to eq(Live.name(klass, 'gotten'))
    end
  end

  describe 'aliases' do
    it 'add creates the action under the name it was given' do
      added = Live.owns('action', Live.retrying('add') { actions.add(trigger_payload('added')) })
      expect(stored(added)['name']).to eq(Live.name(klass, 'added'))
    end

    it 'destroy removes the action and returns its id' do
      doomed = create_own('doomed', trigger_payload('doomed'))
      expect(Live.retrying('destroy') { actions.destroy(doomed) }).to eq(doomed)
      Live.disown('action', doomed)
      expect(Live.get('action', actionids: [doomed])).to eq([])
    end
  end

  describe 'delete' do
    it 'removes the action and returns its id' do
      disposable = create_own('disposable', trigger_payload('disposable'))
      expect(Live.retrying('delete') { actions.delete(disposable) }).to eq(disposable)
      Live.disown('action', disposable)
      expect(Live.get('action', actionids: [disposable])).to eq([])
    end

    it 'refuses an id no action carries' do
      expect { Live.retrying('delete unknown') { actions.delete(999_999_999) } }
        .to raise_error(ZabbixApi::ApiError, /No permissions to referred object or it does not exist/)
    end
  end

  describe 'aftercare' do
    it 'leaves no action, host group, media type or user group under its prefix once torn down, and the standing hosts and proxy and the stock host group still present' do
      Live.teardown
      expect(Live.get('action', search: { name: Live.prefix(klass) })).to eq([])
      expect(Live.get('hostgroup', search: { name: Live.prefix(klass) })).to eq([])
      expect(Live.get('mediatype', search: { name: Live.prefix(klass) })).to eq([])
      expect(Live.get('usergroup', search: { name: Live.prefix(klass) })).to eq([])
      expect(Live.get('host', filter: { host: Live::AGENT_HOSTS }).map { |host| host['host'] }).to match_array(Live::AGENT_HOSTS)
      expect(Live.one('proxy', filter: { name: Live::PROXY_NAME })['name']).to eq(Live::PROXY_NAME)
      expect(Live.one('hostgroup', filter: { name: Live::GROUP_NAME })['name']).to eq(Live::GROUP_NAME)
    end
  end
end
