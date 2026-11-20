# Recorder for ZabbixApi::Proxies: runs the cases below against the server ZABBIX_URL names, through
# the gem itself, and writes spec/fixtures/proxies/crud.json.
#
# The order below is the order spec/zabbixapi/classes/proxies_spec.rb indexes the file in: an
# accepted create, three refused ones and the passive create with the PSK pair, the six reads, the
# issued update, the skipped one and the read-only refusal, a host group and host of this spec's own
# with the proxy that monitors the host and the delete that assignment refuses, the two hosts
# updates, the four upsert branches, the two writing aliases and a delete by String id. Not
# recorded: the ten timeout_* fields and proxy group membership, whose only gem-visible part is the
# pass-through that the PSK and hosts creates already prove and whose server side belongs to the
# acceptance spec; a forced update, which differs from the skipped one only in being issued and
# which the shared example group proves offline; the bulk array forms, which Basic#create and
# #delete handle and Basic's own spec covers.
#
# No recorded call is wrapped in Live.retrying: a retry re-issues every request its block made, so
# a gem call that sends two requests and meets a transient on the second records the first twice.
# A transient database error is raised by the recorder's hook as Live::Recorder::Transient before
# anything is recorded and, being no ApiError, passes the refusal rescues: the run aborts, the
# ensure tears down, and the pre-clean makes a re-run idempotent.
#
# Not a spec - RSpec collects *_spec.rb only - but RuboCop lints it. Run it from the gem's root:
#
#   ZABBIX_URL=<url> ZABBIX_TOKEN=<token> bundle exec ruby spec/recorders/proxies_recorder.rb
#   ZABBIX_SPEC_STAGE=1 in front writes the file to /tmp instead and prints its path.
require 'zabbixapi'
require_relative '../support/fixtures'
require_relative '../support/live/live'
require_relative '../support/live/recorder'

klass = 'proxies'
proxies = Live.session.proxies
psk_identity = Live.name(klass, 'psk')
psk = '0123456789abcdef0123456789abcdef'

# Hosts before proxies, because a proxy that monitors a host cannot be deleted, and the host group
# last, because a host cannot be left without one.
Live.preclean(klass, 'host')
Live.preclean(klass, 'proxy')
Live.preclean(klass, 'hostgroup')

Live::Recorder.start!
begin
  # create: the accepted minimum, an active proxy
  active = Live.owns('proxy', proxies.create(name: Live.name(klass, 'active'), operating_mode: 0))

  # create, refused: the name is taken
  begin
    proxies.create(name: Live.name(klass, 'active'), operating_mode: 0)
  rescue ZabbixApi::ApiError
    nil
  end

  # create, refused: tls_connect PSK on an active proxy, which the proxy object reference does not
  # document
  begin
    proxies.create(name: Live.name(klass, 'psk-active'), operating_mode: 0, tls_connect: 2, tls_psk_identity: psk_identity, tls_psk: psk)
  rescue ZabbixApi::ApiError
    nil
  end

  # create, refused: custom_timeouts 1 without the timeout_* fields it requires
  begin
    proxies.create(name: Live.name(klass, 'notimeouts'), operating_mode: 0, custom_timeouts: 1)
  rescue ZabbixApi::ApiError
    nil
  end

  # create: a passive proxy with its address and the write-only PSK pair
  Live.owns('proxy', proxies.create(name: Live.name(klass, 'passive'), operating_mode: 1, address: '10.1.2.3', port: '10061', tls_connect: 2, tls_psk_identity: psk_identity, tls_psk: psk))

  # the reads
  proxies.get_full_data(name: Live.name(klass, 'passive'))
  proxies.get_id(name: Live.name(klass, 'active'))
  proxies.get_id(name: Live.name(klass, 'absent'))
  proxies.dump_by_id(proxyid: active)
  proxies.get_raw(output: %w[name operating_mode], proxyids: [active])
  proxies.all

  # update, issued: the description differs from the dump
  proxies.update(proxyid: active, description: 'desc v1')

  # update, skipped: the payload now matches the dump, so only the dump goes out
  proxies.update(proxyid: active, description: 'desc v1')

  # update, refused: version, which the proxy object reference marks read-only, with a value that
  # differs from the dump
  begin
    proxies.update(proxyid: active, version: 987_654_321)
  rescue ZabbixApi::ApiError
    nil
  end

  # a host of this spec's own, in a group of its own, for the documented hosts parameter
  group = Live.owns('hostgroup', Live.session.hostgroups.create(name: Live.name(klass, 'group')))
  host = Live.owns('host', Live.session.hosts.create(host: Live.name(klass, 'host'), groups: [{ groupid: group }]))

  # create: hosts assigns the host to the proxy being created
  monitoring = Live.owns('proxy', proxies.create(name: Live.name(klass, 'withhost'), operating_mode: 0, hosts: [{ hostid: host }]))

  # delete, refused: the proxy monitors a host, which the proxy.delete reference does not document
  begin
    proxies.delete(monitoring)
  rescue ZabbixApi::ApiError
    nil
  end

  # update: hosts reassigns the host and an empty array unassigns it; a dump cannot show either,
  # so neither update is ever skipped
  proxies.update(proxyid: active, hosts: [{ hostid: host }])
  proxies.update(proxyid: active, hosts: [])

  # create_or_update, update branch: the name exists and the description differs
  proxies.create_or_update(name: Live.name(klass, 'passive'), description: 'via cou')

  # create_or_update, create branch, then get_or_create on that same name, which finds it and
  # creates nothing
  Live.owns('proxy', proxies.create_or_update(name: Live.name(klass, 'upserted'), operating_mode: 0))
  proxies.get_or_create(name: Live.name(klass, 'upserted'))

  # get_or_create, create branch
  Live.owns('proxy', proxies.get_or_create(name: Live.name(klass, 'gotten'), operating_mode: 0))

  # the two writing aliases, and the id type a delete answers for an Integer
  added = Live.owns('proxy', proxies.add(name: Live.name(klass, 'added'), operating_mode: 0))
  proxies.destroy(added)
  Live.disown('proxy', added)

  # delete with a String id, for the type the server answers in that case
  disposable = Live.owns('proxy', proxies.create(name: Live.name(klass, 'disposable'), operating_mode: 0))
  proxies.delete(disposable.to_s)
  Live.disown('proxy', disposable)

  Live::Recorder.write(klass, 'crud')
ensure
  Live.teardown
end
