# Contract: ZabbixApi::Users
#   evidence: spec/fixtures/users/crud.json;
#             https://www.zabbix.com/documentation/7.0/en/manual/api/reference/user
#   classes:  hooks, key and keys derived from method_name | create wraps one object and merges no
#             defaults | the four reads and the request each builds | get_id filters on the whole
#             payload and asks for userid and username | all maps the username to an Integer id |
#             update skips an equal payload, issues a differing one, honours force, is issued for a
#             collection no extend dump can show, refuses without an id | the four upsert branches,
#             the id merged in as a String | update_medias: the wire shape, one object per user id,
#             an empty list, the two guards, the nil return | the three aliases | delete sends a
#             bare id and returns an Integer | key normalisation, five entry points, five
#             mechanisms | a refusal reaches error_message, from the first request and from a later
#             one
#   not here: the other create refusals - missing username, the theme enum, the password policy -
#             one representative of "the server refused" kept here and all of them asserted live;
#             the read-only family attempt_clock, attempt_ip, provisioned, ts_provisioned, of which
#             attempt_failed is the member kept; a user updating itself and the blocking of an
#             account after failed logins, which go through user.login and query rather than this
#             class, and the four unwrapped methods unblock, provision, resettotp and
#             checkAuthentication; a password change, which no read can confirm because passwd is
#             write-only; get_id's refusal on more than one match, which usernames being unique
#             server-wide make unreachable here and which Basic's own spec proves; the remaining
#             documented get parameters (mediaids, mediatypeids, sortfield, ...), server behaviour
#             that belongs to the acceptance spec; bulk arrays, which Basic#create and #delete
#             handle and Basic's own spec covers
require 'spec_helper'

RSpec.describe ZabbixApi::Users do
  crud = Fixtures.exchanges('users/crud')
  row = Fixtures.exchange('users/crud', 'user.get', 2)['result'].first
  table = Fixtures.exchange('users/crud', 'user.get', 7)['result']
  renamed = Fixtures.exchange('users/crud', 'user.get', 9)['result'].first
  id = row['userid'].to_i
  name = row['username']
  role = row['roleid'].to_i
  group = Fixtures.exchange('users/crud', 'user.create')['params'].first['usrgrps'].first['usrgrpid']
  # A literal of this spec's own that never leaves the process: the fake client has no server behind
  # it, and the recording carries "<scrubbed>" in its place.
  password = 'zbxapi-spec-users-secret'
  minimal = { username: name, passwd: password, roleid: role, usrgrps: [{ usrgrpid: group }] }

  let(:client) { FakeClient.new(crud) }
  let(:users) { described_class.new(client) }

  it_behaves_like 'a Basic resource', method_name: 'user', identify: 'username', key: 'userid', keys: 'userids', default_options: {}

  it_behaves_like 'an inherited create', payload: minimal, defaults: {}, exchange: Fixtures.exchange('users/crud', 'user.create')
  it_behaves_like 'an inherited delete', id: Fixtures.exchange('users/crud', 'user.delete', 1)['params'].first, exchange: Fixtures.exchange('users/crud', 'user.delete', 1)
  it_behaves_like 'an inherited get_id', identify: 'username', key: 'userid', value: name, rows: Fixtures.exchange('users/crud', 'user.get')['result']
  it_behaves_like 'an inherited all', identify: 'username', key: 'userid', rows: table
  it_behaves_like 'the inherited reads', identify: 'username', key: 'userid', value: name, id: id, rows: [row]
  # usrgrps as the collection: user.get returns it only under selectUsrgrps, so a payload naming it
  # can never be proven equal to the stored state and the update is always issued. medias behaves
  # the same way.
  it_behaves_like 'an update that skips when unchanged', key: 'userid', id: id, dump: [renamed],
                                                         unchanged: { name: renamed['name'] }, changed: { name: "#{renamed['name']}-zwei" },
                                                         collection: { usrgrps: [{ usrgrpid: group }] }
  it_behaves_like 'the aliases', exchanges: crud, payload: { username: name }, id: id

  it_behaves_like 'a lookup that refuses to run blind', method: :dump_by_id, field: 'userid'
  it_behaves_like 'a lookup that refuses to run blind', method: :get_id, field: 'username'
  it_behaves_like 'a lookup that refuses to run blind', method: :update_medias, field: 'userids'

  # One instance per normalisation mechanism rather than per entry point: the plain symbolize_keys
  # of a filter-building read, the conditional one in get_id, require_id! in dump_by_id, the dump
  # comparison in update, and require_field! in this class's own update_medias. create would be a
  # sixth only for a class carrying default_options; without them its mechanism is get_full_data's.
  it_behaves_like 'a key-normalising entry point', method: :get_full_data, payload: { username: name }, exchanges: crud
  it_behaves_like 'a key-normalising entry point', method: :get_id, payload: { username: name }, exchanges: crud
  it_behaves_like 'a key-normalising entry point', method: :dump_by_id, payload: { userid: id }, exchanges: crud
  it_behaves_like 'a key-normalising entry point', method: :update, payload: { userid: id, name: 'Geändert' }, exchanges: crud
  it_behaves_like 'a key-normalising entry point', method: :update_medias, payload: { userids: [id], medias: [{ mediatypeid: 1, sendto: ['first@example.invalid'] }] }, exchanges: crud

  describe '#get_raw' do
    it 'passes selectMedias through and hands the media list back with sendto as an Array' do
      fake = FakeClient.new([Fixtures.exchange('users/crud', 'user.get', 4)])
      target = Fixtures.exchange('users/crud', 'user.get', 4)['result'].first['userid'].to_i

      rows = described_class.new(fake).get_raw(userids: [target], selectMedias: 'extend')
      expect(fake.sent('user.get')).to eq([{ 'userids' => [target], 'selectMedias' => 'extend' }])
      expect(rows.first['medias'].first['sendto']).to eq(['first@example.invalid'])
    end
  end

  describe '#update' do
    it 'raises before any request when the payload carries no userid, naming the guard it came from' do
      expect { users.update(name: 'Geändert') }.to raise_error(ZabbixApi::ApiError, /userid not supplied in call to dump_by_id/)
      expect(client.calls).to be_empty
    end
  end

  describe '#update_medias' do
    it 'sends one user.update carrying the user id and the media list, and nothing else' do
      exchange = Fixtures.exchange('users/crud', 'user.update', 4)
      fake = FakeClient.new([exchange])
      target = exchange['result']['userids'].first.to_i

      expect(described_class.new(fake).update_medias(userids: [target], medias: [{ mediatypeid: 1, sendto: ['second@example.invalid'] }])).to eq(target)
      expect(fake.sent('user.update')).to eq([[{ 'userid' => target, 'medias' => [{ 'mediatypeid' => 1, 'sendto' => ['second@example.invalid'] }] }]])
    end

    it 'names every user id of the list in one request and returns the first of them' do
      exchange = Fixtures.exchange('users/crud', 'user.update', 8)
      fake = FakeClient.new([exchange])
      targets = exchange['result']['userids'].map(&:to_i)
      medias = [{ mediatypeid: 1, sendto: ['both@example.invalid'] }]

      expect(described_class.new(fake).update_medias(userids: targets, medias: medias)).to eq(targets.first)
      expect(fake.count('user.update')).to eq(1)
      expect(fake.sent('user.update').first.map { |entry| entry['userid'] }).to eq(targets)
    end

    it 'lets an empty media list through the guard' do
      exchange = Fixtures.exchange('users/crud', 'user.update', 6)
      fake = FakeClient.new([exchange])
      target = exchange['result']['userids'].first.to_i

      expect(described_class.new(fake).update_medias(userids: [target], medias: [])).to eq(target)
      expect(fake.sent('user.update')).to eq([[{ 'userid' => target, 'medias' => [] }]])
    end

    it 'refuses a payload whose list sits under the key media, naming medias and sending nothing' do
      expect { users.update_medias(userids: [id], media: [{ mediatypeid: 1, sendto: ['x@example.invalid'] }]) }
        .to raise_error(ZabbixApi::ApiError, /medias not supplied in call to update_medias/)
      expect(client.calls).to be_empty
    end

    it 'returns nil when the server answers with no object to take ids from' do
      fake = FakeClient.new([{ method: 'user.update', params: {}, result: false }])

      expect(described_class.new(fake).update_medias(userids: [id], medias: [])).to be_nil
    end
  end

  describe '#create_or_update' do
    it 'looks the username up, dumps the user and updates it with the userid merged in as a String' do
      lookup = Fixtures.exchange('users/crud', 'user.get', 15)
      target = lookup['result'].first
      fake = FakeClient.new([lookup, Fixtures.exchange('users/crud', 'user.get', 16), Fixtures.exchange('users/crud', 'user.update', 9)])

      expect(described_class.new(fake).create_or_update(username: target['username'], surname: 'Upsert')).to eq(target['userid'].to_i)
      expect(fake.sent('user.get')).to eq([{ 'filter' => { 'username' => target['username'] }, 'output' => %w[userid username] },
                                           { 'filter' => { 'userid' => target['userid'] }, 'output' => 'extend' }])
      expect(fake.sent('user.update')).to eq([[{ 'username' => target['username'], 'surname' => 'Upsert', 'userid' => target['userid'] }]])
    end

    it 'creates the payload untouched when the username exists nowhere, and issues no update' do
      created = Fixtures.exchange('users/crud', 'user.create', 9)
      fake = FakeClient.new([Fixtures.exchange('users/crud', 'user.get', 17), created])
      unseen = created['params'].first['username']
      payload = minimal.merge(username: unseen)

      expect(described_class.new(fake).create_or_update(payload)).to eq(created['result']['userids'].first.to_i)
      expect(fake.sent('user.create')).to eq([[JSON.parse(JSON.generate(payload))]])
      expect(fake.count('user.update')).to eq(0)
    end
  end

  describe '#get_or_create' do
    it 'returns the id the lookup found and creates nothing' do
      found = Fixtures.exchange('users/crud', 'user.get', 13)
      target = found['result'].first
      fake = FakeClient.new([found])

      expect(described_class.new(fake).get_or_create(username: target['username'], passwd: password)).to eq(target['userid'].to_i)
      expect(fake.count('user.create')).to eq(0)
    end

    it 'creates when the lookup finds nothing, and filters on the username alone while doing so' do
      created = Fixtures.exchange('users/crud', 'user.create', 8)
      fake = FakeClient.new([Fixtures.exchange('users/crud', 'user.get', 14), created])
      unseen = created['params'].first['username']

      expect(described_class.new(fake).get_or_create(minimal.merge(username: unseen))).to eq(created['result']['userids'].first.to_i)
      expect(fake.sent('user.get')).to eq([{ 'filter' => { 'username' => unseen }, 'output' => %w[userid username] }])
    end
  end

  describe '#delete' do
    it 'returns an Integer id although user.delete answers a String whichever type it was given' do
      integer = Fixtures.exchange('users/crud', 'user.delete', 1)
      string = Fixtures.exchange('users/crud', 'user.delete', 2)
      expect([integer['params'].first, string['params'].first]).to match([an_instance_of(Integer), an_instance_of(String)])
      expect([integer['result']['userids'].first, string['result']['userids'].first]).to all(be_a(String))

      by_integer = FakeClient.new([integer])
      by_string = FakeClient.new([string])
      expect(described_class.new(by_integer).delete(integer['params'].first)).to eq(integer['params'].first)
      expect(described_class.new(by_string).delete(string['params'].first)).to eq(string['params'].first.to_i)
      expect(by_string.sent('user.delete')).to eq([[string['params'].first]])
    end
  end

  describe 'a refusal the server sent back' do
    it "reaches the caller as an ApiError whose error_message joins the server's message and data" do
      fake = FakeClient.new([Fixtures.exchange('users/crud', 'user.create', 1)])

      expect { described_class.new(fake).create(minimal) }
        .to raise_error(ZabbixApi::ApiError) { |error| expect(error.error_message).to match(/\AInvalid params\.: User with username .* already exists\.\z/) }
    end

    it 'reaches the caller from the second request too, the dump before it having succeeded' do
      fake = FakeClient.new([Fixtures.exchange('users/crud', 'user.get', 12), Fixtures.exchange('users/crud', 'user.update', 3)])

      expect { described_class.new(fake).update(userid: id, attempt_failed: 3) }
        .to raise_error(ZabbixApi::ApiError) { |error| expect(error.error_message).to match(/unexpected parameter .attempt_failed/) }
      expect(fake.count('user.get')).to eq(1)
    end
  end
end
