# Contract: ZabbixApi::Mediatypes live
#   evidence: https://www.zabbix.com/documentation/7.0/en/manual/api/reference/mediatype
#   classes:  create stores a transport and the server's own defaults, status 1 pending | a webhook
#             stores its script and its parameters, which extend returns | a string-keyed payload
#             reaches the server | refusals: a transport requirement absent and the same one empty,
#             a duplicate name, the value the type enum skips, a range, a gated property outside and
#             at its own default, the conditional requirement the mediatype object reference marks
#             merely supported | passwd comes back readable, pending | reads by name, by id, the
#             three selects, the filter and the count, and the two blind-lookup guards | update by
#             id and by name, the copy the override writes into, unchanged and forced,
#             message_templates replacing, an unknown name, a refused value | the four upsert
#             branches | the writing aliases | delete removes, an unknown id draws the generic
#             refusal | aftercare
#   not here: the hook values and the wire shapes, asserted offline; that an unchanged update sends
#             no request, visible only in the traffic and asserted offline; the remaining enum,
#             range and conditional probes, one representative per enforcement style kept; sortfield
#             and the other passthrough get parameters, three representatives kept; a user whose
#             media references a media type, which shows that delete is not blocked and that userids
#             narrows: the cascade is a property of user, not of this wrapper; the stock population
#             count, a server-wide count this suite never asserts
require 'spec_helper'

RSpec.describe 'ZabbixApi::Mediatypes live', type: :acceptance do
  klass = 'mediatypes'

  # The transport minimum the mediatype object reference requires of each type. Everything points
  # into the reserved .invalid domain, and the password is a literal of the spec's own, never a real
  # one.
  email_base = { type: 0, smtp_server: 'smtp.example.invalid', smtp_email: 'zbxapi-spec@example.invalid' }
  webhook_base = { type: 4, script: 'return 1;' }
  secret = 'zbxapi-spec-mediatypes-secret'

  before(:all) do
    Live.preclean(klass, 'mediatype')
    @mail = Live.owns('mediatype', Live.retrying('create mail') { Live.session.mediatypes.create(email_base.merge(name: Live.name(klass, 'mail'))) })
    @hook = Live.owns('mediatype', Live.retrying('create hook') do
      Live.session.mediatypes.create(webhook_base.merge(name: Live.name(klass, 'hook'), parameters: [{ name: 'Message', value: '{ALERT.MESSAGE}' }]))
    end)
    @secret = Live.owns('mediatype', Live.retrying('create secret') do
      Live.session.mediatypes.create(email_base.merge(name: Live.name(klass, 'secret'), smtp_authentication: 1, username: 'zbxapi-spec', passwd: secret))
    end)
  end

  after(:all) do
    Live.teardown
    Live.preclean(klass, 'mediatype')
  end

  let(:mediatypes) { Live.session.mediatypes }

  describe 'create' do
    it 'stores the Email transport under the id it returned, with the defaults the server applies itself' do
      stored = Live.one('mediatype', mediatypeids: [@mail])
      expect(stored['name']).to eq(Live.name(klass, 'mail'))
      expect(stored['type']).to eq('0')
      expect([stored['smtp_server'], stored['smtp_email']]).to eq(['smtp.example.invalid', 'zbxapi-spec@example.invalid'])
      expect(stored['smtp_port']).to eq('25')
      expect([stored['maxsessions'], stored['maxattempts'], stored['attempt_interval'], stored['provider']]).to eq(%w[1 3 10s 0])
    end

    it 'creates the media type enabled, as the mediatype object reference documents status 0 by default' do
      pending 'a media type created without a status reads back 1, Disabled, and no change log records it'
      expect(Live.one('mediatype', mediatypeids: [@mail])['status']).to eq('0')
    end

    it 'stores a webhook script and its parameters, which extend returns without message_templates' do
      stored = Live.one('mediatype', mediatypeids: [@hook])
      expect(stored['script']).to eq('return 1;')
      expect(stored['timeout']).to eq('30s')
      expect(stored['parameters']).to eq([{ 'name' => 'Message', 'value' => '{ALERT.MESSAGE}' }])
      expect(stored).not_to have_key('message_templates')
    end

    it 'accepts a string-keyed payload and the server stores the same transport' do
      created = Live.owns('mediatype', Live.retrying('create strings') do
        mediatypes.create('name' => Live.name(klass, 'strings'), 'type' => 1, 'exec_path' => 'notify.sh')
      end)
      stored = Live.one('mediatype', mediatypeids: [created])
      expect([stored['name'], stored['type'], stored['exec_path']]).to eq([Live.name(klass, 'strings'), '1', 'notify.sh'])
    end

    it 'refuses an Email type whose transport requirement is absent' do
      expect { Live.retrying('create no smtp_server') { mediatypes.create(name: Live.name(klass, 'nosmtp'), type: 0, smtp_email: 'zbxapi-spec@example.invalid') } }
        .to raise_error(ZabbixApi::ApiError, /the parameter .*smtp_server.* is missing/)
    end

    it 'refuses the same requirement sent empty' do
      expect { Live.retrying('create empty smtp_server') { mediatypes.create(email_base.merge(name: Live.name(klass, 'emptysmtp'), smtp_server: '')) } }
        .to raise_error(ZabbixApi::ApiError, /cannot be empty/)
    end

    it 'refuses a name another media type already carries' do
      expect { Live.retrying('create duplicate') { mediatypes.create(email_base.merge(name: Live.name(klass, 'mail'))) } }
        .to raise_error(ZabbixApi::ApiError, /already exists/)
    end

    it 'refuses type 3, the value the enum skips' do
      expect { Live.retrying('create type 3') { mediatypes.create(email_base.merge(name: Live.name(klass, 'type3'), type: 3)) } }
        .to raise_error(ZabbixApi::ApiError, %r{Invalid parameter .*/1/type})
    end

    it 'refuses a maxattempts outside the documented 1-100' do
      expect { Live.retrying('create maxattempts') { mediatypes.create(email_base.merge(name: Live.name(klass, 'attempts'), maxattempts: 101)) } }
        .to raise_error(ZabbixApi::ApiError, %r{Invalid parameter .*/1/maxattempts.*value must be one of 1-100})
    end

    it 'refuses a timeout other than its own default on a non-webhook' do
      expect { Live.retrying('create timeout 20s') { mediatypes.create(email_base.merge(name: Live.name(klass, 'timeout'), timeout: '20s')) } }
        .to raise_error(ZabbixApi::ApiError, %r{Invalid parameter .*/1/timeout.*value must be 30})
    end

    it 'accepts that same gated timeout at its own default' do
      created = Live.owns('mediatype', Live.retrying('create timeout 30s') { mediatypes.create(email_base.merge(name: Live.name(klass, 'timeout30'), timeout: '30s')) })
      expect(Live.one('mediatype', mediatypeids: [created])['timeout']).to eq('30s')
    end

    it 'requires event_menu_url once show_event_menu is 1, where the mediatype object reference marks it merely supported' do
      expect { Live.retrying('create event menu') { mediatypes.create(webhook_base.merge(name: Live.name(klass, 'menu'), show_event_menu: 1)) } }
        .to raise_error(ZabbixApi::ApiError, /the parameter .*event_menu_url.* is missing/)
    end
  end

  describe 'the SMTP password' do
    it 'stores the username and returns it' do
      expect(Live.one('mediatype', mediatypeids: [@secret])['username']).to eq('zbxapi-spec')
    end

    it 'does not return the password' do
      pending 'mediatype.get returns passwd in plaintext under output extend'
      expect(Live.one('mediatype', mediatypeids: [@secret])['passwd']).not_to eq(secret)
    end
  end

  describe 'reads' do
    it 'get_id returns the id stored under that name' do
      expect(Live.retrying('get_id') { mediatypes.get_id(name: Live.name(klass, 'mail')) }).to eq(@mail)
    end

    it 'get_id returns the id when the payload carries a second key the media type does not match' do
      expect(Live.retrying('get_id scoped') { mediatypes.get_id(name: Live.name(klass, 'mail'), maxattempts: 99) }).to eq(@mail)
    end

    it 'get_id returns nil for a name no media type carries' do
      expect(Live.retrying('get_id absent') { mediatypes.get_id(name: Live.name(klass, 'absent')) }).to be_nil
    end

    it 'get_id refuses to run blind' do
      expect { mediatypes.get_id({}) }.to raise_error(ZabbixApi::ApiError, /name not supplied/)
    end

    it 'get_full_data returns the media type under its name with type, smtp_server and parameters' do
      found = Live.retrying('get_full_data') { mediatypes.get_full_data(name: Live.name(klass, 'mail')) }
      expect(found.map { |type| type['mediatypeid'].to_i }).to eq([@mail])
      expect(found.first.keys).to include('type', 'smtp_server', 'parameters')
    end

    it 'dump_by_id finds the media type, and extend carries parameters but not message_templates' do
      dumped = Live.retrying('dump_by_id') { mediatypes.dump_by_id(mediatypeid: @mail) }.first
      expect(dumped['name']).to eq(Live.name(klass, 'mail'))
      expect(dumped).to have_key('parameters')
      expect(dumped).not_to have_key('message_templates')
    end

    it 'dump_by_id refuses to run blind' do
      expect { mediatypes.dump_by_id({}) }.to raise_error(ZabbixApi::ApiError, /mediatypeid not supplied/)
    end

    it 'get_raw adds the three documented selects under the property names the mediatype.get reference promises' do
      row = Live.retrying('selects') do
        mediatypes.get_raw(mediatypeids: [@mail], selectMessageTemplates: 'extend', selectUsers: 'extend', selectActions: 'extend')
      end.first
      expect(row.keys).to include('message_templates', 'users', 'actions')
    end

    it 'get_raw narrows by a filter on type, and counts over the ids it is given' do
      names = Live.retrying('filter type') { mediatypes.get_raw(output: ['name'], filter: { type: 4 }) }.map { |type| type['name'] }
      expect(names).to include(Live.name(klass, 'hook'))
      expect(names).not_to include(Live.name(klass, 'mail'))
      expect(Live.retrying('countOutput') { mediatypes.get_raw(countOutput: true, mediatypeids: [@mail, @hook]) }).to eq('2')
    end

    it 'all maps its own name to the id as an Integer and carries the stock media type Email beside it' do
      table = Live.retrying('all') { mediatypes.all }
      expect(table[Live.name(klass, 'mail')]).to eq(@mail)
      expect(table).to include('Email')
    end
  end

  describe 'update' do
    it 'writes a property by id and it reads back' do
      expect(Live.retrying('update by id') { mediatypes.update(mediatypeid: @hook, description: 'by id') }).to eq(@hook)
      expect(Live.one('mediatype', mediatypeids: [@hook])['description']).to eq('by id')
    end

    it 'resolves the id from the name when the payload carries none' do
      expect(Live.retrying('update by name') { mediatypes.update(name: Live.name(klass, 'mail'), description: 'by name') }).to eq(@mail)
      expect(Live.one('mediatype', mediatypeids: [@mail])['description']).to eq('by name')
    end

    it 'reaches the second name when the same hash is reused for it, and not the first' do
      payload = { name: Live.name(klass, 'mail'), description: 'first pass' }
      Live.retrying('update reused first') { mediatypes.update(payload) }
      payload[:name] = Live.name(klass, 'hook')
      payload[:description] = 'second pass'
      expect(Live.retrying('update reused second') { mediatypes.update(payload) }).to eq(@hook)
      expect(Live.one('mediatype', mediatypeids: [@mail])['description']).to eq('first pass')
      expect(Live.one('mediatype', mediatypeids: [@hook])['description']).to eq('second pass')
    end

    it 'returns the id and leaves the object exactly as it was when nothing differs' do
      before_state = Live.one('mediatype', mediatypeids: [@mail])
      expect(Live.retrying('update unchanged') { mediatypes.update(mediatypeid: @mail, name: Live.name(klass, 'mail')) }).to eq(@mail)
      expect(Live.one('mediatype', mediatypeids: [@mail])).to eq(before_state)
    end

    it 'accepts a forced update that changes nothing, and the object survives it unchanged' do
      before_state = Live.one('mediatype', mediatypeids: [@mail])
      expect(Live.retrying('update forced') { mediatypes.update({ mediatypeid: @mail, name: Live.name(klass, 'mail') }, true) }).to eq(@mail)
      expect(Live.one('mediatype', mediatypeids: [@mail])).to eq(before_state)
    end

    it 'replaces message_templates rather than merging them' do
      two = [{ eventsource: 0, recovery: 0, subject: 'problem', message: 'M' },
             { eventsource: 0, recovery: 1, subject: 'resolved', message: 'M' }]
      Live.retrying('update templates two') { mediatypes.update(mediatypeid: @mail, message_templates: two) }
      expect(Live.one('mediatype', mediatypeids: [@mail], selectMessageTemplates: 'extend')['message_templates'].size).to eq(2)

      Live.retrying('update templates one') { mediatypes.update(mediatypeid: @mail, message_templates: [two.first]) }
      stored = Live.one('mediatype', mediatypeids: [@mail], selectMessageTemplates: 'extend')['message_templates']
      expect(stored.map { |item| item['subject'] }).to eq(['problem'])
    end

    it 'raises for a name no media type carries, naming the name' do
      expect { Live.retrying('update absent') { mediatypes.update(name: Live.name(klass, 'absent'), description: 'nowhere') } }
        .to raise_error(ZabbixApi::ApiError, /\Ano mediatype found with name "#{Live.name(klass, 'absent')}"\z/)
    end

    it 'refuses a value outside the documented range and the stored one survives' do
      expect { Live.retrying('update maxattempts') { mediatypes.update(mediatypeid: @mail, maxattempts: 101) } }
        .to raise_error(ZabbixApi::ApiError, %r{Invalid parameter .*/1/maxattempts.*value must be one of 1-100})
      expect(Live.one('mediatype', mediatypeids: [@mail])['maxattempts']).to eq('3')
    end
  end

  describe 'upserts' do
    it 'create_or_update changes a property of an existing name without making a second media type' do
      expect(Live.retrying('upsert update') { mediatypes.create_or_update(name: Live.name(klass, 'hook'), description: 'per upsert') }).to eq(@hook)
      expect(Live.one('mediatype', mediatypeids: [@hook])['description']).to eq('per upsert')
      expect(Live.count('mediatype', filter: { name: Live.name(klass, 'hook') })).to eq(1)
    end

    it 'create_or_update creates when the name exists nowhere' do
      created = Live.owns('mediatype', Live.retrying('upsert create') { mediatypes.create_or_update(email_base.merge(name: Live.name(klass, 'cou'))) })
      stored = Live.one('mediatype', mediatypeids: [created])
      expect([stored['name'], stored['smtp_server']]).to eq([Live.name(klass, 'cou'), 'smtp.example.invalid'])
    end

    it 'get_or_create returns the existing id and leaves one media type of that name' do
      expect(Live.retrying('get_or_create found') { mediatypes.get_or_create(email_base.merge(name: Live.name(klass, 'mail'))) }).to eq(@mail)
      expect(Live.count('mediatype', filter: { name: Live.name(klass, 'mail') })).to eq(1)
    end

    it 'get_or_create creates when the name exists nowhere' do
      created = Live.owns('mediatype', Live.retrying('get_or_create create') { mediatypes.get_or_create(type: 1, exec_path: 'notify.sh', name: Live.name(klass, 'goc')) })
      stored = Live.one('mediatype', mediatypeids: [created])
      expect([stored['name'], stored['exec_path']]).to eq([Live.name(klass, 'goc'), 'notify.sh'])
    end
  end

  describe 'aliases' do
    it 'add creates the media type under the name it was given' do
      added = Live.owns('mediatype', Live.retrying('add') { mediatypes.add(email_base.merge(name: Live.name(klass, 'added'))) })
      expect(Live.one('mediatype', mediatypeids: [added])['name']).to eq(Live.name(klass, 'added'))
    end

    it 'destroy removes the media type and returns its id' do
      doomed = Live.owns('mediatype', Live.retrying('create doomed') { mediatypes.create(email_base.merge(name: Live.name(klass, 'doomed'))) })
      expect(Live.retrying('destroy') { mediatypes.destroy(doomed) }).to eq(doomed)
      Live.disown('mediatype', doomed)
      expect(Live.get('mediatype', mediatypeids: [doomed])).to eq([])
    end
  end

  describe 'delete' do
    it 'removes the media type and returns its id as an Integer' do
      disposable = Live.owns('mediatype', Live.retrying('create disposable') { mediatypes.create(email_base.merge(name: Live.name(klass, 'disposable'))) })
      expect(Live.retrying('delete') { mediatypes.delete(disposable) }).to eq(disposable)
      Live.disown('mediatype', disposable)
      expect(Live.get('mediatype', mediatypeids: [disposable])).to eq([])
    end

    it 'refuses an id no media type carries' do
      expect { Live.retrying('delete unknown') { mediatypes.delete(999999999) } }
        .to raise_error(ZabbixApi::ApiError, /No permissions to referred object or it does not exist/)
    end
  end

  describe 'aftercare' do
    it 'leaves no media type under its prefix once torn down, and the standing hosts and proxy and the stock media type Email still present' do
      Live.teardown
      expect(Live.get('mediatype', search: { name: Live.prefix(klass) })).to eq([])
      expect(Live.one('mediatype', filter: { name: 'Email' })['name']).to eq('Email')
      expect(Live.get('host', filter: { host: Live::AGENT_HOSTS }).map { |host| host['host'] }).to match_array(Live::AGENT_HOSTS)
      expect(Live.one('proxy', filter: { name: Live::PROXY_NAME })['name']).to eq(Live::PROXY_NAME)
    end
  end
end
