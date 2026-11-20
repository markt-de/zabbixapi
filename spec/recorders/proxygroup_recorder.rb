# Recorder for ZabbixApi::Proxygroup: runs the cases below against the server ZABBIX_URL names,
# through the gem itself, and writes spec/fixtures/proxygroup/crud.json.
#
# The order below is the order the unit spec indexes the file in: two accepted creates and four
# refusals, the six reads, the skipped update, the issued one and two refused ones, the four upsert
# branches, the two aliases that write, and three deletes - through destroy with an Integer id, with
# a String id, and refused because a proxy belongs to the group. Not recorded: a forced update,
# which differs from the skipped one only in being issued and which the shared example group proves
# offline; the accepted range bounds and the user macro in failover_delay, which are server
# behaviour the acceptance spec asserts; the bulk array forms, which Basic#create and #delete handle
# and Basic's own spec covers.
#
# No recorded call is wrapped in Live.retrying: a retry re-issues every request its block made, so
# a gem call that sends two requests and meets a transient on the second records the first twice.
# A transient database error is raised by the recorder's hook as Live::Recorder::Transient before
# anything is recorded and, being no ApiError, passes the refusal rescues: the run aborts, the
# ensure tears down, and the pre-clean makes a re-run idempotent.
#
# Not a spec - RSpec collects *_spec.rb only - but RuboCop lints it. Run it from the gem's root:
#
#   ZABBIX_URL=<url> ZABBIX_TOKEN=<token> bundle exec ruby spec/recorders/proxygroup_recorder.rb
#   ZABBIX_SPEC_STAGE=1 in front writes the file to /tmp instead and prints its path.
require 'zabbixapi'
require_relative '../support/fixtures'
require_relative '../support/live/live'
require_relative '../support/live/recorder'

klass = 'proxygroup'
proxygroup = Live.session.proxygroup

# Proxies before proxy groups: a group a proxy belongs to cannot be deleted.
Live.preclean(klass, 'proxy')
Live.preclean(klass, 'proxygroup')

Live::Recorder.start!
begin
  # create: the accepted minimum, every other property left to the server's defaults
  one = Live.owns('proxygroup', proxygroup.create(name: Live.name(klass, 'one')))

  # create: every documented writable property in one call
  Live.owns('proxygroup', proxygroup.create(name: Live.name(klass, 'full'), description: 'every documented field', failover_delay: '5m', min_online: '10'))

  # create, refused: proxy_groupid is read-only here, although update requires it
  begin
    proxygroup.create(name: Live.name(klass, 'gid'), proxy_groupid: 999_999)
  rescue ZabbixApi::ApiError
    nil
  end

  # create, refused: state is read-only
  begin
    proxygroup.create(name: Live.name(klass, 'state'), state: 3)
  rescue ZabbixApi::ApiError
    nil
  end

  # create, refused: name is required
  begin
    proxygroup.create(description: 'nameless')
  rescue ZabbixApi::ApiError
    nil
  end

  # create, refused: the name is taken
  begin
    proxygroup.create(name: Live.name(klass, 'one'))
  rescue ZabbixApi::ApiError
    nil
  end

  # the reads
  proxygroup.get_full_data(name: Live.name(klass, 'full'))
  proxygroup.get_id(name: Live.name(klass, 'one'))
  proxygroup.get_id(name: Live.name(klass, 'absent'))
  proxygroup.dump_by_id(proxy_groupid: one)
  proxygroup.get_raw(output: ['name'], proxy_groupids: [one])
  proxygroup.all

  # update, skipped: the payload already matches the dump, so only the dump goes out
  proxygroup.update(proxy_groupid: one, name: Live.name(klass, 'one'))

  # update, issued: three properties in one request
  proxygroup.update(proxy_groupid: one, description: 'batched', failover_delay: '2m', min_online: '4')

  # update, refused: failover_delay below the documented 10s bound; the server answers
  # `Invalid parameter "/1/failover_delay": value must be one of 10-900.`, the range in seconds
  begin
    proxygroup.update(proxy_groupid: one, failover_delay: '9s')
  rescue ZabbixApi::ApiError
    nil
  end

  # update, refused: state is read-only on update too
  begin
    proxygroup.update(proxy_groupid: one, state: 3)
  rescue ZabbixApi::ApiError
    nil
  end

  # create_or_update, update branch: the name exists and min_online differs
  proxygroup.create_or_update(name: Live.name(klass, 'full'), min_online: '11')

  # create_or_update, create branch, then get_or_create on that same name, which finds it and
  # creates nothing
  Live.owns('proxygroup', proxygroup.create_or_update(name: Live.name(klass, 'three')))
  proxygroup.get_or_create(name: Live.name(klass, 'three'))

  # get_or_create, create branch
  Live.owns('proxygroup', proxygroup.get_or_create(name: Live.name(klass, 'four')))

  # the two writing aliases, and the id type a delete echoes for an Integer
  added = Live.owns('proxygroup', proxygroup.add(name: Live.name(klass, 'added')))
  proxygroup.destroy(added)
  Live.disown('proxygroup', added)

  # delete with a String id, for the type the server echoes in that case
  disposable = Live.owns('proxygroup', proxygroup.create(name: Live.name(klass, 'disposable')))
  proxygroup.delete(disposable.to_s)
  Live.disown('proxygroup', disposable)

  # delete, refused: a proxy belongs to the group, a constraint the proxygroup.delete reference does
  # not document
  inuse = Live.owns('proxygroup', proxygroup.create(name: Live.name(klass, 'inuse')))
  Live.owns('proxy', Live.session.proxies.create(name: Live.name(klass, 'member'), operating_mode: 0, proxy_groupid: inuse, local_address: 'proxy', local_port: '10051'))
  begin
    proxygroup.delete(inuse)
  rescue ZabbixApi::ApiError
    nil
  end

  Live::Recorder.write(klass, 'crud')
ensure
  Live.teardown
end
