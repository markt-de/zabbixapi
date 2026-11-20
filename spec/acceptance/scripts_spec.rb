# Contract: ZabbixApi::Scripts live
#   evidence: https://www.zabbix.com/documentation/7.0/en/manual/api/reference/script
#   classes:  create stores the minimum and every documented default | one script per remaining
#             type: webhook parameters, SSH credentials, URL | the scope enum at its three values
#             and at its hole | the type enum at its hole and at the one pair the matrix excludes |
#             required, conditionally required and gated properties, one refusal each | one name
#             under two menu paths | the five reads | update writes, skips, forces, and clears
#             parameters when the type leaves 5 | the four upsert branches | the writing aliases |
#             delete, and what an action operation blocks | getscriptsbyhost in both forms,
#             narrowed, and with {MANUALINPUT} expanded | getscriptsbyevents in both forms and
#             narrowed, against the standing problem, and the scopes it lists that execute would
#             refuse | execute: webhook, shell, manual input, and eight refusals | aftercare
#   not here: the hooks and the blind-lookup refusals of get_id and of a direct dump_by_id call,
#             which need no server and belong to the unit spec; the full 18-pair type x scope matrix
#             and every enum at both bounds, reduced to the representatives above; Telnet, which
#             answers an interface-less host exactly as SSH does; IPMI, which the server refuses
#             while StartIPMIPollers is 0; execute against an event, because this spec owns none and
#             the standing problem is only ever read - getscriptsbyevents only reads it; execute_on
#             0, which against a host no agent polls hangs until the HTTP timeout
#
# Safety: every scope 2 script carries the groupid of a host group this spec created, every execute
# targets this spec's own interface-less host, and the only bodies that ever run are a printf with a
# literal and a webhook returning a literal. No stock script is executed, and the one action created
# is disabled and filtered onto this spec's own host group.
# The one exception is the scope 4 script getscriptsbyevents needs: a script scoped to a host group
# is offered for an event only when the event's host is in that group, so it carries the group of
# the standing problem's host rather than this spec's. It is a webhook returning a literal, it is
# never executed, and it goes away with the teardown; the standing problem itself is only ever read.
# script and action are in Live::CONTAINERS, so before(:all) pre-cleans all four containers this
# spec creates, the referencing object before the one it names: an action operation blocks its
# script's delete, and a host group's delete is refused while an action or a script references it or
# a host belongs to it alone. The order is therefore action, script, host, hostgroup, and a crashed
# run is swept away instead of failing the next one on a duplicate name.
require 'spec_helper'

RSpec.describe 'ZabbixApi::Scripts live', type: :acceptance do
  klass = 'scripts'
  server_command = %q(printf 'zbxapi\n')
  input_command = %q(printf '%s\n' '{MANUALINPUT}')
  webhook_code = "Zabbix.log(3, '[zbxapi-spec] webhook probe');\nreturn 'zbxapi';"
  missing = 999999999

  before(:all) do
    Live.preclean(klass, 'action')
    Live.preclean(klass, 'script')
    Live.preclean(klass, 'host')
    Live.preclean(klass, 'hostgroup')
    scripts = Live.session.scripts
    @group = Live.owns('hostgroup', Live.retrying('create group') { Live.session.hostgroups.create(name: Live.name(klass, 'hg')) })
    @other_group = Live.owns('hostgroup', Live.retrying('create other group') { Live.session.hostgroups.create(name: Live.name(klass, 'other-hg')) })
    # No interface, no template, no item: nothing polls it and there is no address for the server
    # to connect to, which is what makes the SSH refusal safe to provoke.
    @host = Live.owns('host', Live.retrying('create host') { Live.session.hosts.create(host: Live.name(klass, 'target'), groups: [{ groupid: @group }]) })

    @one = Live.owns('script', Live.retrying('create one') { scripts.create(name: Live.name(klass, 'one'), scope: 1, type: 0, command: server_command) })
    # Everything execute is ever pointed at is created here, so that one wait covers them all.
    @webhook = Live.owns('script', Live.retrying('create webhook') { scripts.create(name: Live.name(klass, 'x-webhook'), scope: 2, type: 5, command: webhook_code, timeout: '10s', groupid: @group) })
    @shell = Live.owns('script', Live.retrying('create shell') { scripts.create(name: Live.name(klass, 'x-shell'), scope: 2, type: 0, execute_on: 1, command: server_command, groupid: @group) })
    @prompt = Live.owns('script', Live.retrying('create prompt') do
      scripts.create(name: Live.name(klass, 'x-prompt'), scope: 2, type: 0, execute_on: 1, command: input_command, groupid: @group,
                     confirmation: 'run with {MANUALINPUT}?', manualinput: 1, manualinput_prompt: 'value?',
                     manualinput_validator: '^[a-z]+$', manualinput_validator_type: 0, manualinput_default_value: 'zbxapi')
    end)
    @url = Live.owns('script', Live.retrying('create url') { scripts.create(name: Live.name(klass, 'x-url'), scope: 2, type: 6, url: 'http://127.0.0.1/zbxapi-spec', groupid: @group) })
    @ssh = Live.owns('script', Live.retrying('create ssh') { scripts.create(name: Live.name(klass, 'x-ssh'), scope: 2, type: 2, command: server_command, username: 'zbxapi-spec', password: 'zbxapi-spec-secret', port: '2222', groupid: @group) })
    @foreign = Live.owns('script', Live.retrying('create foreign') { scripts.create(name: Live.name(klass, 'x-foreign'), scope: 2, type: 5, command: webhook_code, timeout: '10s', groupid: @other_group) })

    # getscriptsbyevents needs an event and this spec owns none, so it reads the standing problem. A
    # script scoped to a host group reaches an event only when the event's host is in that group, so
    # this one carries that host's group rather than @group.
    standing_host = Live.one('host', filter: { host: Live::STANDING_PROBLEM_HOST }, output: %w[hostid host])
    raise "the stock host #{Live::STANDING_PROBLEM_HOST}, which carries the standing problem, is not on this server" if standing_host.nil?

    standing = Live.one('problem', hostids: [standing_host['hostid'].to_i], output: %w[eventid name])
    raise "no problem stands on #{Live::STANDING_PROBLEM_HOST}; getscriptsbyevents has no event without one" if standing.nil?

    @event = standing['eventid'].to_i
    @event_group = Live.one('host', hostids: [standing_host['hostid'].to_i], selectHostGroups: %w[groupid name])['hostgroups'].first['groupid'].to_i
    @event_script = Live.owns('script', Live.retrying('create event script') { scripts.create(name: Live.name(klass, 'x-event'), scope: 4, type: 5, command: webhook_code, timeout: '10s', groupid: @event_group) })

    # script.execute is answered by the Zabbix server, not by the frontend, so a host the API
    # created a moment ago answers "Unknown host identifier." until the server's configuration cache
    # has caught up.
    Live.wait('the server configuration cache to know the target host', max: 180, step: 5) do
      scripts.execute(scriptid: @webhook, hostid: @host)
      true
    rescue ZabbixApi::ApiError => e
      raise unless e.message.include?('Unknown host identifier')

      false
    end
  end

  after(:all) { Live.teardown }

  let(:scripts) { Live.session.scripts }

  describe 'create' do
    it 'stores the minimum and every default the script object reference documents' do
      stored = Live.one('script', scriptids: [@one])
      expect(stored['name']).to eq(Live.name(klass, 'one'))
      expect(stored.values_at('scope', 'type', 'command')).to eq(['1', '0', server_command])
      expect(stored.values_at('execute_on', 'groupid', 'usrgrpid', 'host_access', 'new_window', 'manualinput', 'manualinput_validator_type', 'timeout', 'authtype')).to eq(%w[2 0 0 2 1 0 0 30s 0])
      expect(stored.values_at('menu_path', 'description', 'confirmation', 'url', 'port', 'username', 'manualinput_prompt')).to all(eq(''))
      expect(stored['parameters']).to eq([])
    end

    it 'stores a type 0 script at each of the three scopes, although the script object reference lists type 0 for scope 1 alone' do
      stored = [2, 4].map do |scope|
        id = Live.owns('script', Live.retrying("create scope #{scope}") { scripts.create(name: Live.name(klass, "scope#{scope}"), scope: scope, type: 0, command: server_command, groupid: @group) })
        Live.one('script', scriptids: [id])['scope']
      end
      expect([Live.one('script', scriptids: [@one])['scope']] + stored).to eq(%w[1 2 4])
    end

    it 'refuses scope 3, the hole in the middle of the scope enum' do
      expect { Live.retrying('scope 3 refusal') { scripts.create(name: Live.name(klass, 'scope3'), scope: 3, type: 0, command: server_command) } }
        .to raise_error(ZabbixApi::ApiError, %r{/1/scope.*value must be one of})
    end

    it 'refuses type 4, the hole in the middle of the type enum' do
      expect { Live.retrying('type 4 refusal') { scripts.create(name: Live.name(klass, 'type4'), scope: 1, type: 4, command: server_command) } }
        .to raise_error(ZabbixApi::ApiError, %r{/1/type.*value must be one of})
    end

    it 'refuses a URL script at scope 1' do
      expect { Live.retrying('url at scope 1 refusal') { scripts.create(name: Live.name(klass, 'url1'), scope: 1, type: 6, url: 'http://127.0.0.1/zbxapi-spec') } }
        .to raise_error(ZabbixApi::ApiError, %r{/1/type.*value must be one of})
    end

    it 'stores a webhook with its timeout and parameters' do
      id = Live.owns('script', Live.retrying('create parameters') do
        scripts.create(name: Live.name(klass, 'parameters'), scope: 1, type: 5, command: webhook_code, timeout: '45s',
                       parameters: [{ name: 'token', value: '{$ZBXAPI_SPEC}' }, { name: 'host', value: '{HOST.HOST}' }])
      end)
      stored = Live.one('script', scriptids: [id])
      expect(stored['timeout']).to eq('45s')
      # script.get returns the parameters in no guaranteed order.
      expect(stored['parameters'].map { |parameter| parameter['name'] }).to match_array(%w[host token])
      expect(stored['parameters'].to_h { |parameter| [parameter['name'], parameter['value']] }).to eq('token' => '{$ZBXAPI_SPEC}', 'host' => '{HOST.HOST}')
    end

    it 'stores the 30s default for a webhook created without the timeout the script object reference marks required' do
      id = Live.owns('script', Live.retrying('create no timeout') { scripts.create(name: Live.name(klass, 'notimeout'), scope: 1, type: 5, command: webhook_code) })
      expect(Live.one('script', scriptids: [id])['timeout']).to eq('30s')
    end

    it 'stores an SSH script with its username, port and authentication method' do
      stored = Live.one('script', scriptids: [@ssh])
      expect(stored.values_at('type', 'username', 'port', 'authtype')).to eq(%w[2 zbxapi-spec 2222 0])
    end

    it 'does not return that SSH password' do
      pending 'script.get returns password, publickey and privatekey verbatim, and the script object reference marks none of them write-only'
      expect(Live.one('script', scriptids: [@ssh])['password']).to eq('')
    end

    it 'stores a URL script and leaves its command empty' do
      stored = Live.one('script', scriptids: [@url])
      expect(stored.values_at('type', 'url', 'command')).to eq(['6', 'http://127.0.0.1/zbxapi-spec', ''])
    end

    it 'refuses menu_path outside the two scopes it is gated to, rather than ignoring it' do
      expect { Live.retrying('menu_path refusal') { scripts.create(name: Live.name(klass, 'menu'), scope: 1, type: 0, command: server_command, menu_path: 'zbxapi-spec/deep') } }
        .to raise_error(ZabbixApi::ApiError, %r{/1/menu_path.*value must be empty})
    end

    it 'refuses a create that names no scope at all' do
      expect { Live.retrying('missing scope refusal') { scripts.create(name: Live.name(klass, 'noscope'), type: 0, command: server_command) } }
        .to raise_error(ZabbixApi::ApiError, /the parameter.*scope.*is missing/)
    end

    it 'refuses a URL script that names no url' do
      expect { Live.retrying('missing url refusal') { scripts.create(name: Live.name(klass, 'nourl'), scope: 2, type: 6, groupid: @group) } }
        .to raise_error(ZabbixApi::ApiError, /the parameter.*url.*is missing/)
    end

    it 'refuses the read-only scriptid' do
      expect { Live.retrying('scriptid on create refusal') { scripts.create(name: Live.name(klass, 'readonly'), scope: 1, type: 0, command: server_command, scriptid: missing) } }
        .to raise_error(ZabbixApi::ApiError, /unexpected parameter.*scriptid/)
    end

    it 'refuses a second script of the same name at the same menu path' do
      expect { Live.retrying('duplicate name refusal') { scripts.create(name: Live.name(klass, 'one'), scope: 1, type: 0, command: server_command) } }
        .to raise_error(ZabbixApi::ApiError, /already exists/)
    end

    it 'accepts that same name under another menu path; get_id then refuses, reporting two matches, and all keeps one of the pair' do
      pair = %w[a b].map do |path|
        Live.owns('script', Live.retrying("create dup #{path}") { scripts.create(name: Live.name(klass, 'dup'), scope: 2, type: 0, command: server_command, groupid: @group, menu_path: "zbxapi-spec/#{path}") })
      end
      expect(Live.count('script', filter: { name: Live.name(klass, 'dup') })).to eq(2)
      expect { Live.retrying('get_id dup') { scripts.get_id(name: Live.name(klass, 'dup')) } }.to raise_error(ZabbixApi::ApiError, /\Aget_id matched 2 script objects, not one \(scriptid /)
      expect(pair).to include(Live.retrying('all dup') { scripts.all }[Live.name(klass, 'dup')])
    end
  end

  describe 'reads' do
    it 'get_id returns the id stored under that name' do
      expect(Live.retrying('get_id') { scripts.get_id(name: Live.name(klass, 'one')) }).to eq(@one)
    end

    it 'get_id returns nil for a name no script carries' do
      expect(Live.retrying('get_id absent') { scripts.get_id(name: Live.name(klass, 'absent')) }).to be_nil
    end

    it 'get_full_data returns the script under its name with scope, type and parameters' do
      found = Live.retrying('get_full_data') { scripts.get_full_data(name: Live.name(klass, 'one')) }
      expect(found.map { |script| script['scriptid'].to_i }).to eq([@one])
      expect(found.first).to include('scope', 'type', 'parameters')
    end

    it 'dump_by_id finds the script by its id' do
      expect(Live.retrying('dump_by_id') { scripts.dump_by_id(scriptid: @one) }.first['name']).to eq(Live.name(klass, 'one'))
    end

    it "all maps the name of this spec's script to its Integer id and includes the stock Ping script" do
      table = Live.retrying('all') { scripts.all }
      expect(table[Live.name(klass, 'one')]).to eq(@one)
      expect(table).to include('Ping')
    end

    it 'get_raw passes a documented parameter through: selectHostGroups on a group-scoped script' do
      row = Live.retrying('get_raw') { scripts.get_raw(scriptids: [@webhook], selectHostGroups: 'extend') }.first
      expect(row['hostgroups'].map { |group| group['groupid'].to_i }).to eq([@group])
    end
  end

  describe 'update' do
    it 'writes the property it was given and leaves the command alone' do
      id = Live.owns('script', Live.retrying('create updatable') { scripts.create(name: Live.name(klass, 'updatable'), scope: 1, type: 0, command: server_command, description: 'before') })
      expect(Live.retrying('update') { scripts.update(scriptid: id, description: 'after') }).to eq(id)
      stored = Live.one('script', scriptids: [id])
      expect(stored.values_at('description', 'command')).to eq(['after', server_command])
    end

    it 'returns the id and leaves the script exactly as it was when nothing differs' do
      before_state = Live.one('script', scriptids: [@one])
      expect(Live.retrying('update unchanged') { scripts.update(scriptid: @one, name: Live.name(klass, 'one')) }).to eq(@one)
      expect(Live.one('script', scriptids: [@one])).to eq(before_state)
    end

    it 'returns the id for a forced update, and the name reads back as sent' do
      expect(Live.retrying('update forced') { scripts.update({ scriptid: @one, name: Live.name(klass, 'one') }, true) }).to eq(@one)
      expect(Live.one('script', scriptids: [@one])['name']).to eq(Live.name(klass, 'one'))
    end

    it 'clears the parameters when the type moves away from 5, as the script.update reference says' do
      id = Live.owns('script', Live.retrying('create convertible') do
        scripts.create(name: Live.name(klass, 'convertible'), scope: 1, type: 5, command: webhook_code, timeout: '30s', parameters: [{ name: 'token', value: '{$ZBXAPI_SPEC}' }])
      end)
      expect(Live.one('script', scriptids: [id])['parameters'].size).to eq(1)
      Live.retrying('update type') { scripts.update(scriptid: id, type: 0, command: server_command) }
      expect(Live.one('script', scriptids: [id])['parameters']).to eq([])
    end

    it 'raises when the payload names no scriptid' do
      expect { scripts.update(description: 'after') }.to raise_error(ZabbixApi::ApiError, /scriptid not supplied in call to dump_by_id/)
    end
  end

  describe 'upserts' do
    it 'create_or_update changes a property of an existing name without creating a second script' do
      expect(Live.retrying('upsert update') { scripts.create_or_update(name: Live.name(klass, 'one'), scope: 1, type: 0, command: server_command, description: 'upserted') }).to eq(@one)
      expect(Live.one('script', scriptids: [@one])['description']).to eq('upserted')
      expect(Live.count('script', filter: { name: Live.name(klass, 'one') })).to eq(1)
    end

    it 'create_or_update creates when the name is new' do
      created = Live.owns('script', Live.retrying('upsert create') { scripts.create_or_update(name: Live.name(klass, 'upserted'), scope: 1, type: 0, command: server_command) })
      expect(Live.one('script', scriptids: [created])['name']).to eq(Live.name(klass, 'upserted'))
    end

    it 'get_or_create returns the existing id and leaves one script of that name' do
      expect(Live.retrying('get_or_create found') { scripts.get_or_create(name: Live.name(klass, 'one'), scope: 1, type: 0, command: server_command) }).to eq(@one)
      expect(Live.count('script', filter: { name: Live.name(klass, 'one') })).to eq(1)
    end

    it 'get_or_create creates when the name is new' do
      created = Live.owns('script', Live.retrying('get_or_create create') { scripts.get_or_create(name: Live.name(klass, 'gotten'), scope: 1, type: 0, command: server_command) })
      expect(Live.one('script', scriptids: [created])['name']).to eq(Live.name(klass, 'gotten'))
    end
  end

  describe 'aliases' do
    it 'add creates the script and destroy removes it' do
      added = Live.owns('script', Live.retrying('add') { scripts.add(name: Live.name(klass, 'added'), scope: 1, type: 0, command: server_command) })
      expect(Live.one('script', scriptids: [added])['name']).to eq(Live.name(klass, 'added'))
      expect(Live.retrying('destroy') { scripts.destroy(added) }).to eq(added)
      Live.disown('script', added)
      expect(Live.get('script', scriptids: [added])).to eq([])
    end
  end

  describe 'delete' do
    it 'removes the script and returns its id' do
      disposable = Live.owns('script', Live.retrying('create disposable') { scripts.create(name: Live.name(klass, 'disposable'), scope: 1, type: 0, command: server_command) })
      expect(Live.retrying('delete') { scripts.delete(disposable) }).to eq(disposable)
      Live.disown('script', disposable)
      expect(Live.get('script', scriptids: [disposable])).to eq([])
    end

    it 'is refused, and so is a scope change, while an action operation references the script, and succeeds once the action is gone' do
      referenced = Live.owns('script', Live.retrying('create referenced') { scripts.create(name: Live.name(klass, 'operation'), scope: 1, type: 0, command: server_command) })
      action = Live.owns('action', Live.retrying('create action') do
        Live.raw('action.create', name: Live.name(klass, 'action'), eventsource: 0, status: 1, esc_period: '1h',
                                  filter: { evaltype: 0, conditions: [{ conditiontype: 0, operator: 0, value: @group.to_s }] },
                                  operations: [{ operationtype: 1, opcommand: { scriptid: referenced }, opcommand_hst: [{ hostid: 0 }] }])['actionids'][0].to_i
      end)
      expect(Live.one('action', actionids: [action])['status']).to eq('1')

      expect { Live.retrying('referenced delete refusal') { scripts.delete(referenced) } }.to raise_error(ZabbixApi::ApiError, /is used in action operation/)
      expect { Live.retrying('referenced scope refusal') { scripts.update({ scriptid: referenced, scope: 2, groupid: @group }, true) } }.to raise_error(ZabbixApi::ApiError, /Cannot update script scope/)
      expect(Live.one('script', scriptids: [referenced])['scope']).to eq('1')

      Live.retrying('delete action') { Live.raw('action.delete', [action]) }
      Live.disown('action', action)
      expect(Live.retrying('delete referenced') { scripts.delete(referenced) }).to eq(referenced)
      Live.disown('script', referenced)
      expect(Live.get('script', scriptids: [referenced])).to eq([])
    end

    # Its own throwaway pair, so a surprise success would damage nothing the rest of the file relies
    # on.
    it 'refuses the delete of a host group a script is scoped to, as the hostgroup.delete reference says' do
      group = Live.owns('hostgroup', Live.retrying('create scoped group') { Live.session.hostgroups.create(name: Live.name(klass, 'scoped-hg')) })
      Live.owns('script', Live.retrying('create scoped script') { scripts.create(name: Live.name(klass, 'x-scoped'), scope: 2, type: 5, command: webhook_code, timeout: '10s', groupid: group) })

      expect { Live.retrying('scoped group delete refusal') { Live.session.hostgroups.delete(group) } }
        .to raise_error(ZabbixApi::ApiError, /cannot be deleted, because it is used in a global script/)
    end

    it 'refuses a scriptid no script carries' do
      expect { Live.retrying('missing delete refusal') { scripts.delete(missing) } }.to raise_error(ZabbixApi::ApiError, /No permissions to referred object/)
    end
  end

  describe 'getscriptsbyhost' do
    it "answers an object keyed by host id, holding the webhook scoped to the host's group" do
      offered = Live.retrying('getscriptsbyhost') { scripts.getscriptsbyhost(hostid: @host) }
      expect(offered.keys).to eq([@host.to_s])
      expect(offered[@host.to_s].map { |script| script['scriptid'].to_i }).to include(@webhook)
    end

    it 'omits the script scoped to a group this host is not in' do
      offered = Live.retrying('getscriptsbyhost foreign') { scripts.getscriptsbyhost(hostid: @host) }
      expect(offered[@host.to_s].map { |script| script['scriptid'].to_i }).not_to include(@foreign)
    end

    it 'agrees with itself whether it is given the object or an array of objects' do
      one = Live.retrying('getscriptsbyhost object') { scripts.getscriptsbyhost(hostid: @host) }
      many = Live.retrying('getscriptsbyhost array') { scripts.getscriptsbyhost([{ hostid: @host }]) }
      expect(many.keys).to eq([@host.to_s])
      expect(many).to eq(one)
    end

    it 'narrows to the one script a scriptid names' do
      offered = Live.retrying('getscriptsbyhost narrowed') { scripts.getscriptsbyhost(hostid: @host, scriptid: @webhook) }
      expect(offered[@host.to_s].map { |script| script['scriptid'].to_i }).to eq([@webhook])
    end

    it 'expands a given manualinput into the confirmation text' do
      offered = Live.retrying('getscriptsbyhost manualinput') { scripts.getscriptsbyhost(hostid: @host, scriptid: @prompt, manualinput: 'zbxapi') }
      expect(offered[@host.to_s].first['confirmation']).to eq('run with zbxapi?')
    end

    it 'refuses a bare array of host ids' do
      expect { Live.retrying('bare array refusal') { scripts.getscriptsbyhost([@host]) } }.to raise_error(ZabbixApi::ApiError, /an array is expected/)
    end

    # The script.getscriptsbyhosts reference marks hostid required.
    it 'accepts an empty object and answers an empty Array, where the script.getscriptsbyhosts reference promises an object' do
      expect(Live.retrying('empty object') { scripts.getscriptsbyhost({}) }).to eq([])
    end
  end

  describe 'getscriptsbyevents' do
    it "answers an object keyed by event id, holding this spec's scope 4 script" do
      offered = Live.retrying('getscriptsbyevents') { scripts.getscriptsbyevents(eventid: @event) }
      expect(offered.keys).to eq([@event.to_s])
      expect(offered[@event.to_s].map { |script| script['scriptid'].to_i }).to include(@event_script)
    end

    # Scopes 1 and 4 come from this spec's own scripts and scope 2 from the stock scripts, which are
    # available on all host groups: every scope 2 script this spec creates is scoped to a host group
    # the standing problem's host is not in.
    it 'lists scripts of scope 1 and 2 beside scope 4' do
      offered = Live.retrying('getscriptsbyevents scopes') { scripts.getscriptsbyevents(eventid: @event) }
      expect(offered[@event.to_s].map { |script| script['scope'] }.uniq).to include('1', '2', '4')
    end

    it 'agrees with itself whether it is given the object or an array of objects' do
      one = Live.retrying('getscriptsbyevents object') { scripts.getscriptsbyevents(eventid: @event) }
      many = Live.retrying('getscriptsbyevents array') { scripts.getscriptsbyevents([{ eventid: @event }]) }
      expect(many.keys).to eq([@event.to_s])
      expect(many).to eq(one)
    end

    it 'narrows to the one script a scriptid names' do
      offered = Live.retrying('getscriptsbyevents narrowed') { scripts.getscriptsbyevents(eventid: @event, scriptid: @event_script) }
      expect(offered[@event.to_s].map { |script| script['scriptid'].to_i }).to eq([@event_script])
    end

    it 'refuses a bare array of event ids' do
      expect { Live.retrying('bare array refusal') { scripts.getscriptsbyevents([@event]) } }.to raise_error(ZabbixApi::ApiError, /an array is expected/)
    end

    it 'accepts an empty object and answers an empty Array, where the script.getscriptsbyevents reference promises an object' do
      expect(Live.retrying('empty object') { scripts.getscriptsbyevents({}) }).to eq([])
    end
  end

  describe 'execute' do
    it 'runs a webhook and returns its value with a debug object holding its log line' do
      result = Live.retrying('execute webhook') { scripts.execute(scriptid: @webhook, hostid: @host) }
      expect(result['response']).to eq('success')
      expect(result['value']).to eq('zbxapi')
      expect(result['debug'].keys).to match_array(%w[logs ms])
      expect(result['debug']['logs'].first['message']).to eq('[zbxapi-spec] webhook probe')
    end

    it "runs a shell command, keeps its trailing newline and answers debug as an empty Array, although the manual's Alerts → Scripts page says trailing whitespace is truncated" do
      result = Live.retrying('execute shell') { scripts.execute(scriptid: @shell, hostid: @host) }
      expect(result['response']).to eq('success')
      expect(result['value']).to eq("zbxapi\n")
      expect(result['debug']).to eq([])
    end

    it 'substitutes a manualinput the validator accepts into the command' do
      result = Live.retrying('execute manualinput') { scripts.execute(scriptid: @prompt, hostid: @host, manualinput: 'zbxapi') }
      expect(result['value']).to eq("zbxapi\n")
    end

    it 'refuses a manualinput the validator rejects' do
      expect { Live.retrying('manualinput refusal') { scripts.execute(scriptid: @prompt, hostid: @host, manualinput: '123') } }
        .to raise_error(ZabbixApi::ApiError, /user input failed validation/)
    end

    it 'refuses a URL script, which the script.execute reference excludes' do
      expect { Live.retrying('url execute refusal') { scripts.execute(scriptid: @url, hostid: @host) } }.to raise_error(ZabbixApi::ApiError, /Cannot execute URL type script/)
    end

    it 'refuses an action-operation script against a host' do
      expect { Live.retrying('scope 1 execute refusal') { scripts.execute(scriptid: @one, hostid: @host) } }.to raise_error(ZabbixApi::ApiError, /not allowed in manual host action/)
    end

    it 'refuses SSH against a host that has no interface to reach' do
      expect { Live.retrying('ssh refusal') { scripts.execute(scriptid: @ssh, hostid: @host) } }.to raise_error(ZabbixApi::ApiError, /No interface defined for host/)
    end

    it 'refuses a script scoped to a group the target host is not in' do
      expect { Live.retrying('foreign group refusal') { scripts.execute(scriptid: @foreign, hostid: @host) } }.to raise_error(ZabbixApi::ApiError, /No permissions to referred object/)
    end

    it 'refuses a call without a scriptid, and one that names neither host nor event' do
      expect { Live.retrying('missing scriptid refusal') { scripts.execute(hostid: @host) } }.to raise_error(ZabbixApi::ApiError, /the parameter.*scriptid.*is missing/)
      expect { Live.retrying('missing target refusal') { scripts.execute(scriptid: @webhook) } }.to raise_error(ZabbixApi::ApiError, /the parameter.*eventid.*is missing/)
    end

    it 'refuses a scriptid no script carries' do
      expect { Live.retrying('unknown script execute refusal') { scripts.execute(scriptid: missing, hostid: @host) } }.to raise_error(ZabbixApi::ApiError, /No permissions to referred object/)
    end
  end

  describe 'aftercare' do
    it 'leaves no script, action, host or host group under its prefix once torn down, and the standing hosts and proxy still present' do
      Live.teardown
      expect(Live.get('script', search: { name: Live.prefix(klass) })).to eq([])
      expect(Live.get('action', search: { name: Live.prefix(klass) })).to eq([])
      expect(Live.get('host', search: { host: Live.prefix(klass) })).to eq([])
      expect(Live.get('hostgroup', search: { name: Live.prefix(klass) })).to eq([])
      expect(Live.get('host', filter: { host: Live::AGENT_HOSTS }).map { |host| host['host'] }).to match_array(Live::AGENT_HOSTS)
      expect(Live.one('proxy', filter: { name: Live::PROXY_NAME })['name']).to eq(Live::PROXY_NAME)
    end
  end
end
