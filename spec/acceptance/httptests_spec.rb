# Contract: ZabbixApi::HttpTests live
#   evidence: https://www.zabbix.com/documentation/7.0/en/manual/api/reference/httptest
#   classes:  the minimal create and the defaults the server fills in, scenario and step | the
#             optional parameters stored, the two passwords aside, collections included | a
#             string-keyed payload | one enum bound accepted, one refused, one range refused at both
#             ends | refusals: the empty steps and a name the caller omitted, a name taken on that
#             host | the same name on another host | reads: scoped, unscoped, absent, by id, raw
#             with a select, all | update: one field, several at once, unchanged, forced, steps
#             replace, hostid refused, no id | the four upsert branches, the twin, both key styles |
#             the web items a scenario creates and loses with it | delete, and an unknown id |
#             aftercare
#   not here: the status and delay defaults, because every scenario this spec creates fixes both
#             (the server itself would poll it), so this layer can never observe them; how many
#             requests a call made - the update skip and the upsert branches are counted offline;
#             the remaining authentication values, the other three enums and the full step matrix,
#             one representative kept per kind; the template scenario and its inherited copy
require 'spec_helper'

RSpec.describe 'ZabbixApi::HttpTests live', type: :acceptance do
  klass = 'httptests'

  # One scenario step, reaching nothing: example.invalid is reserved and cannot resolve.
  def step(number, name, extra = {})
    { name: name, url: "http://example.invalid/#{name}", no: number }.merge(extra)
  end

  # Every scenario this spec creates is inert, since the server itself would poll it: disabled,
  # hourly at most, every step unreachable.
  def scenario(hostid, name, extra = {})
    { hostid: hostid, name: Live.name('httptests', name), status: 1, delay: '1h', steps: [step(1, 'home')] }.merge(extra)
  end

  before(:all) do
    Live.preclean(klass, 'host')
    Live.preclean(klass, 'hostgroup')
    @group = Live.owns('hostgroup', Live.retrying('create group') { Live.session.hostgroups.create(name: Live.name(klass, 'grp')) })
    @first = Live.owns('host', Live.retrying('create h1') { Live.session.hosts.create(host: Live.name(klass, 'h1'), groups: [{ groupid: @group }], description: 'spec fixture: no interface, web scenarios only') })
    @second = Live.owns('host', Live.retrying('create h2') { Live.session.hosts.create(host: Live.name(klass, 'h2'), groups: [{ groupid: @group }], description: 'spec fixture: no interface, web scenarios only') })
    # Web scenarios are contents: they are not registered, they go away with their host.
    @base = Live.retrying('create base') { Live.session.httptests.create(scenario(@first, 'base')) }
    @twin = Live.retrying('create twin') { Live.session.httptests.create(scenario(@second, 'base')) }
  end

  after(:all) { Live.teardown }

  let(:httptests) { Live.session.httptests }

  describe 'create' do
    it 'stores the name and hostid and leaves agent, retries, authentication and both verify flags at the server default, with no parent template' do
      stored = Live.one('httptest', httptestids: [@base])
      expect(stored['name']).to eq(Live.name(klass, 'base'))
      expect(stored['hostid'].to_i).to eq(@first)
      expect(stored.slice('agent', 'retries', 'authentication', 'verify_peer', 'verify_host', 'templateid'))
        .to eq('agent' => 'Zabbix', 'retries' => '1', 'authentication' => '0', 'verify_peer' => '0', 'verify_host' => '0', 'templateid' => '0')
    end

    it 'stores the step with the defaults its own table documents, and an empty status_codes' do
      stored = Live.one('httptest', httptestids: [@base], selectSteps: 'extend')['steps'].first
      expect(stored.slice('timeout', 'follow_redirects', 'retrieve_mode')).to eq('timeout' => '15s', 'follow_redirects' => '1', 'retrieve_mode' => '0')
      # The httptest object reference documents no default for status_codes; the "200" in the
      # httptest.get reference's example is a value that example's caller passed.
      expect(stored['status_codes']).to eq('')
    end

    it 'stores nine optional properties, the variables, headers and tags, and both steps it sends' do
      detailed = step(1, 'first', required: 'ok', status_codes: '200,201', timeout: '30s', follow_redirects: 0, retrieve_mode: 2, posts: 'a=b', headers: [{ name: 'X-Step', value: 'one' }], variables: [{ name: '{one}', value: '1' }], query_fields: [{ name: 'q', value: 'v' }])
      full = scenario(@first, 'full',
                      agent: 'Zabbix 7.0', retries: 3, authentication: 1, http_user: 'zbxapi-spec',
                      http_proxy: 'http://proxy.example.invalid:3128', ssl_cert_file: 'cert.pem',
                      ssl_key_file: 'key.pem', verify_peer: 1, verify_host: 1,
                      variables: [{ name: '{var}', value: '12' }],
                      headers: [{ name: 'X-Zbxapi-Spec', value: klass }],
                      tags: [{ tag: 'zbxapi-spec', value: klass }],
                      steps: [detailed, step(2, 'second')])
      id = Live.retrying('create full') { httptests.create(full) }

      stored = Live.one('httptest', httptestids: [id], selectSteps: 'extend', selectTags: 'extend')
      expect(stored.slice('agent', 'retries', 'authentication', 'http_user', 'http_proxy', 'ssl_cert_file', 'ssl_key_file', 'verify_peer', 'verify_host'))
        .to eq('agent' => 'Zabbix 7.0', 'retries' => '3', 'authentication' => '1', 'http_user' => 'zbxapi-spec',
               'http_proxy' => 'http://proxy.example.invalid:3128', 'ssl_cert_file' => 'cert.pem',
               'ssl_key_file' => 'key.pem', 'verify_peer' => '1', 'verify_host' => '1')
      expect(stored['variables']).to eq([{ 'name' => '{var}', 'value' => '12' }])
      expect(stored['headers']).to eq([{ 'name' => 'X-Zbxapi-Spec', 'value' => klass }])
      expect(stored['tags']).to eq([{ 'tag' => 'zbxapi-spec', 'value' => klass }])
      # Steps come back in the order they were sent, not sorted by no, and these two are sent in the
      # order of no; every extra field of the first survives.
      expect(stored['steps'].map { |one| one['name'] }).to eq(%w[first second])
      expect(stored['steps'].first.slice('required', 'status_codes', 'timeout', 'follow_redirects', 'retrieve_mode', 'posts'))
        .to eq('required' => 'ok', 'status_codes' => '200,201', 'timeout' => '30s', 'follow_redirects' => '0', 'retrieve_mode' => '2', 'posts' => 'a=b')
      expect(stored['steps'].first.slice('headers', 'variables', 'query_fields'))
        .to eq('headers' => [{ 'name' => 'X-Step', 'value' => 'one' }], 'variables' => [{ 'name' => '{one}', 'value' => '1' }], 'query_fields' => [{ 'name' => 'q', 'value' => 'v' }])
    end

    it 'accepts a string-keyed payload and stores the same scenario' do
      id = Live.retrying('create strings') do
        httptests.create('hostid' => @first, 'name' => Live.name(klass, 'strings'), 'status' => 1, 'delay' => '1h',
                         'steps' => [{ 'name' => 'home', 'url' => 'http://example.invalid/home', 'no' => 1 }])
      end
      stored = Live.one('httptest', httptestids: [id])
      expect([stored['name'], stored['hostid'].to_i]).to eq([Live.name(klass, 'strings'), @first])
    end

    it 'refuses the empty steps the forced placeholder sends when the caller omits them' do
      expect { Live.retrying('create nosteps') { httptests.create(hostid: @first, name: Live.name(klass, 'nosteps'), status: 1, delay: '1h') } }
        .to raise_error(ZabbixApi::ApiError, %r{/1/steps.*cannot be empty})
    end

    it 'refuses a name the caller omitted, the forced placeholder being dropped' do
      expect { Live.retrying('create noname') { httptests.create(hostid: @first, status: 1, delay: '1h', steps: [step(1, 'home')]) } }
        .to raise_error(ZabbixApi::ApiError, /parameter .*name.* is missing/)
    end

    it 'refuses a name a scenario of the same host already carries' do
      expect { Live.retrying('create duplicate') { httptests.create(scenario(@first, 'base')) } }.to raise_error(ZabbixApi::ApiError, /already exists/)
    end

    it 'carries that same name on the other host' do
      expect(Live.one('httptest', httptestids: [@twin]).values_at('name', 'hostid')).to eq([Live.name(klass, 'base'), @second.to_s])
    end

    it 'accepts the top of the documented authentication enum and stores it' do
      id = Live.retrying('create auth') { httptests.create(scenario(@first, 'auth', authentication: 4)) }
      expect(Live.one('httptest', httptestids: [id])['authentication']).to eq('4')
    end

    it 'refuses an authentication value one above the documented enum' do
      expect { Live.retrying('create badauth') { httptests.create(scenario(@first, 'badauth', authentication: 5)) } }
        .to raise_error(ZabbixApi::ApiError, %r{/1/authentication.*value must be one of})
    end

    it 'refuses a step timeout outside the documented range of 1s to 1h at either end' do
      expect { Live.retrying('create tmin') { httptests.create(scenario(@first, 'tmin', steps: [step(1, 'home', timeout: '0s')])) } }
        .to raise_error(ZabbixApi::ApiError, %r{/1/steps/1/timeout})
      expect { Live.retrying('create tmax') { httptests.create(scenario(@first, 'tmax', steps: [step(1, 'home', timeout: '2h')])) } }
        .to raise_error(ZabbixApi::ApiError, %r{/1/steps/1/timeout})
    end
  end

  describe 'reads' do
    it 'get_id scoped by hostid returns each host scenario of the shared name' do
      expect(Live.retrying('get_id first') { httptests.get_id(name: Live.name(klass, 'base'), hostid: @first) }).to eq(@base)
      expect(Live.retrying('get_id second') { httptests.get_id(name: Live.name(klass, 'base'), hostid: @second) }).to eq(@twin)
    end

    it 'get_id without a hostid refuses, reporting two matches' do
      expect { Live.retrying('get_id unscoped') { httptests.get_id(name: Live.name(klass, 'base')) } }.to raise_error(ZabbixApi::ApiError, /\Aget_id matched 2 httptest objects, not one \(httptestid /)
    end

    it 'get_id returns nil for a name no host carries' do
      expect(Live.retrying('get_id absent') { httptests.get_id(name: Live.name(klass, 'absent')) }).to be_nil
    end

    it 'get_full_data returns the scenarios of that name on both hosts' do
      found = Live.retrying('get_full_data') { httptests.get_full_data(name: Live.name(klass, 'base')) }
      expect(found.map { |one| one['httptestid'].to_i }).to match_array([@base, @twin])
    end

    it 'dump_by_id returns the one scenario of that id with agent, retries, verify_peer and templateid' do
      dumped = Live.retrying('dump_by_id') { httptests.dump_by_id(httptestid: @base) }
      expect(dumped.map { |one| one['httptestid'].to_i }).to eq([@base])
      expect(dumped.first).to include('agent', 'retries', 'verify_peer', 'templateid')
    end

    it 'get_raw passes a documented parameter through: selectSteps in its count form' do
      row = Live.retrying('get_raw') { httptests.get_raw(httptestids: [@twin], output: %w[httptestid], selectSteps: 'count') }.first
      expect(row['steps']).to eq('1')
    end

    it 'all maps the shared name to one of the two Integer ids' do
      table = Live.retrying('all') { httptests.all }
      expect([@base, @twin]).to include(table[Live.name(klass, 'base')])
    end
  end

  describe 'update' do
    it 'writes one property and reads back changed' do
      expect(Live.retrying('update one') { httptests.update(httptestid: @base, retries: 3) }).to eq(@base)
      expect(Live.one('httptest', httptestids: [@base])['retries']).to eq('3')
    end

    it 'writes several properties in one call' do
      expect(Live.retrying('update batch') { httptests.update(httptestid: @base, retries: 4, agent: 'curl', verify_peer: 1) }).to eq(@base)
      expect(Live.one('httptest', httptestids: [@base]).slice('retries', 'agent', 'verify_peer'))
        .to eq('retries' => '4', 'agent' => 'curl', 'verify_peer' => '1')
    end

    it 'returns the id and leaves the scenario exactly as it was when nothing differs' do
      before_state = Live.one('httptest', httptestids: [@base])
      expect(Live.retrying('update unchanged') { httptests.update(httptestid: @base, agent: 'curl') }).to eq(@base)
      expect(Live.one('httptest', httptestids: [@base])).to eq(before_state)
    end

    it 'returns the id for a forced update, and the agent reads back as sent' do
      expect(Live.retrying('update forced') { httptests.update({ httptestid: @base, agent: 'curl' }, true) }).to eq(@base)
      expect(Live.one('httptest', httptestids: [@base])['agent']).to eq('curl')
    end

    it 'replaces the steps instead of merging them' do
      expect(Live.retrying('update steps') { httptests.update(httptestid: @base, steps: [step(1, 'home'), step(2, 'about')]) }).to eq(@base)
      stored = Live.one('httptest', httptestids: [@base], selectSteps: 'extend')['steps'].sort_by { |one| one['no'].to_i }
      expect(stored.map { |one| one['name'] }).to eq(%w[home about])

      expect(Live.retrying('update steps back') { httptests.update(httptestid: @base, steps: [step(1, 'home')]) }).to eq(@base)
      expect(Live.one('httptest', httptestids: [@base], selectSteps: 'count')['steps']).to eq('1')
    end

    it 'refuses a hostid in the payload as an unexpected parameter, and the scenario keeps its host' do
      expect { Live.retrying('update hostid') { httptests.update(httptestid: @base, hostid: @second, agent: 'wget') } }
        .to raise_error(ZabbixApi::ApiError, /unexpected parameter.*hostid/)
      expect(Live.one('httptest', httptestids: [@base])['hostid'].to_i).to eq(@first)
    end

    it 'raises when the payload names no httptestid' do
      expect { httptests.update(agent: 'curl') }.to raise_error(ZabbixApi::ApiError, /httptestid not supplied/)
    end
  end

  describe 'upserts' do
    it 'create_or_update changes the scenario of that host without creating a second one' do
      expect(Live.retrying('upsert update') { httptests.create_or_update(scenario(@first, 'base', agent: 'upserted')) }).to eq(@base)
      expect(Live.one('httptest', httptestids: [@base])['agent']).to eq('upserted')
      expect(Live.count('httptest', hostids: [@first], filter: { name: Live.name(klass, 'base') })).to eq(1)
    end

    it 'create_or_update creates when that host carries no scenario of the name' do
      created = Live.retrying('upsert create') { httptests.create_or_update(scenario(@second, 'upserted')) }
      stored = Live.one('httptest', httptestids: [created])
      expect([stored['name'], stored['hostid'].to_i]).to eq([Live.name(klass, 'upserted'), @second])
    end

    it 'get_or_create returns the existing id of that host and creates nothing' do
      expect(Live.retrying('get_or_create found') { httptests.get_or_create(scenario(@first, 'base')) }).to eq(@base)
      expect(Live.count('httptest', hostids: [@first], filter: { name: Live.name(klass, 'base') })).to eq(1)
    end

    it 'get_or_create creates when that host carries no scenario of the name' do
      created = Live.retrying('get_or_create create') { httptests.get_or_create(scenario(@first, 'gotten')) }
      expect(Live.one('httptest', httptestids: [created])['name']).to eq(Live.name(klass, 'gotten'))
    end

    it 'resolves the same name on the other host to that host scenario' do
      expect(Live.retrying('upsert twin') { httptests.get_or_create(scenario(@second, 'base')) }).to eq(@twin)
    end

    it 'takes a string-keyed payload through the update branch' do
      found = Live.retrying('upsert strings') do
        httptests.create_or_update('hostid' => @first, 'name' => Live.name(klass, 'base'), 'agent' => 'stringy',
                                   'status' => 1, 'delay' => '1h',
                                   'steps' => [{ 'name' => 'home', 'url' => 'http://example.invalid/home', 'no' => 1 }])
      end
      expect(found).to eq(@base)
      expect(Live.one('httptest', httptestids: [@base])['agent']).to eq('stringy')
    end
  end

  describe 'the web items a scenario brings with it' do
    it 'gains nine web items for two steps and loses them with the scenario' do
      before_count = Live.count('item', hostids: [@second], webitems: true, filter: { type: 9 })
      created = Live.retrying('create webitems') { httptests.create(scenario(@second, 'webitems', steps: [step(1, 'home'), step(2, 'about')])) }
      expect(Live.count('item', hostids: [@second], webitems: true, filter: { type: 9 })).to eq(before_count + 9)

      expect(Live.retrying('delete webitems') { httptests.delete(created) }).to eq(created)
      expect(Live.count('item', hostids: [@second], webitems: true, filter: { type: 9 })).to eq(before_count)
    end
  end

  describe 'delete' do
    it 'removes the scenario and returns its id' do
      disposable = Live.retrying('create disposable') { httptests.create(scenario(@first, 'disposable')) }
      expect(Live.retrying('delete') { httptests.delete(disposable) }).to eq(disposable)
      expect(Live.get('httptest', httptestids: [disposable])).to eq([])
    end

    it 'refuses an id no scenario carries' do
      expect { Live.retrying('delete unknown') { httptests.delete(999999999) } }.to raise_error(ZabbixApi::ApiError, /No permissions to referred object or it does not exist/)
    end
  end

  describe 'aftercare' do
    it 'leaves no host, host group or web scenario under its prefix once torn down, and the standing hosts and proxy still present' do
      Live.teardown
      expect(Live.get('host', search: { host: Live.prefix(klass) })).to eq([])
      expect(Live.get('hostgroup', search: { name: Live.prefix(klass) })).to eq([])
      expect(Live.get('httptest', search: { name: Live.prefix(klass) })).to eq([])
      expect(Live.get('host', filter: { host: Live::AGENT_HOSTS }).map { |host| host['host'] }).to match_array(Live::AGENT_HOSTS)
      expect(Live.one('proxy', filter: { name: Live::PROXY_NAME })['name']).to eq(Live::PROXY_NAME)
    end
  end
end
