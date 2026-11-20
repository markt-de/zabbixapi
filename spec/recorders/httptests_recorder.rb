# Recorder for ZabbixApi::HttpTests: runs the cases below against the server ZABBIX_URL names,
# through the gem itself, and writes spec/fixtures/httptests/crud.json.
#
# The order below is the order the unit spec indexes the file in: the accepted minimum, four
# refusals, the twin that carries the same name on another host, the nine reads, the skipped update,
# the issued one, the collection update that can never be skipped, the refused hostid, the four
# upsert branches, the two writing aliases, two accepted deletes and a refused one.
#
# Not recorded: the scaffolding - a host group and two interface-less hosts - which is built before
# the recording starts so the fixture carries httptest traffic only; a forced update, which differs
# from the skipped one only in being issued and which the shared example group proves offline; the
# full documented parameter set and the enum bounds, which are server validation and belong to the
# acceptance spec; the template scenario and its inherited copy.
#
# Every scenario is created inert, since the server itself would poll it: status: 1 (disabled),
# delay: '1h', every step pointed at a name that cannot resolve (RFC 2606).
#
# No recorded call is wrapped in Live.retrying: a retry re-issues every request its block made, so
# a gem call that sends two requests and meets a transient on the second records the first twice.
# A transient database error is raised by the recorder's hook as Live::Recorder::Transient before
# anything is recorded and, being no ApiError, passes the refusal rescues: the run aborts, the
# ensure tears down, and the pre-clean makes a re-run idempotent.
#
# Not a spec - RSpec collects *_spec.rb only - but RuboCop lints it. Run it from the gem's root:
#
#   ZABBIX_URL=<url> ZABBIX_TOKEN=<token> bundle exec ruby spec/recorders/httptests_recorder.rb
#   ZABBIX_SPEC_STAGE=1 in front writes the file to /tmp instead and prints its path.
require 'zabbixapi'
require_relative '../support/fixtures'
require_relative '../support/live/live'
require_relative '../support/live/recorder'

# One scenario step, reaching nothing: example.invalid is reserved and cannot resolve.
def step(number, name, extra = {})
  { name: name, url: "http://example.invalid/#{name}", no: number }.merge(extra)
end

# The inert scenario every case starts from: the three required properties plus the two that keep it
# inert. extra overrides any of them, steps included.
def scenario(hostid, name, extra = {})
  { hostid: hostid, name: name, status: 1, delay: '1h', steps: [step(1, 'home')] }.merge(extra)
end

klass = 'httptests'
httptests = Live.session.httptests

# Hosts before host groups: a group that is a host's only group cannot be deleted.
Live.preclean(klass, 'host')
Live.preclean(klass, 'hostgroup')

# The scaffolding. Web scenarios are contents and are not registered for teardown - they go away
# with the host that carries them.
group = Live.owns('hostgroup', Live.session.hostgroups.create(name: Live.name(klass, 'grp')))
first_host = Live.owns('host', Live.session.hosts.create(host: Live.name(klass, 'h1'), groups: [{ groupid: group }]))
second_host = Live.owns('host', Live.session.hosts.create(host: Live.name(klass, 'h2'), groups: [{ groupid: group }]))

Live::Recorder.start!
begin
  # create: hostid, name and one step are the documented minimum
  base = httptests.create(scenario(first_host, Live.name(klass, 'base')))

  # create, refused: the forced steps: [] default turns an omitted required parameter into an empty one
  begin
    httptests.create(hostid: first_host, name: Live.name(klass, 'nosteps'), status: 1, delay: '1h')
  rescue ZabbixApi::ApiError
    nil
  end

  # create, refused: the forced name: nil default is dropped, so the server answers
  # `Invalid parameter "/1": the parameter "name" is missing.`
  begin
    httptests.create(hostid: first_host, status: 1, delay: '1h', steps: [step(1, 'home')])
  rescue ZabbixApi::ApiError
    nil
  end

  # create, refused: the name is already taken on this host
  begin
    httptests.create(scenario(first_host, Live.name(klass, 'base')))
  rescue ZabbixApi::ApiError
    nil
  end

  # create, refused: a step timeout above the documented maximum of 1h
  begin
    httptests.create(scenario(first_host, Live.name(klass, 'toolong'), steps: [step(1, 'home', timeout: '2h')]))
  rescue ZabbixApi::ApiError
    nil
  end

  # the twin: the same name on the second host, which the server accepts
  httptests.create(scenario(second_host, Live.name(klass, 'base')))

  # the reads
  httptests.get_full_data(name: Live.name(klass, 'base'))
  httptests.get_id(name: Live.name(klass, 'base'), hostid: first_host)
  httptests.get_id(name: Live.name(klass, 'base'), hostid: second_host)
  # unscoped: two hosts carry the name, so one_id! refuses after the exchange is recorded
  begin
    httptests.get_id(name: Live.name(klass, 'base'))
  rescue ZabbixApi::ApiError
    nil
  end
  httptests.get_id(name: Live.name(klass, 'absent'))
  httptests.dump_by_id(httptestid: base)
  httptests.get_raw(output: %w[httptestid name], httptestids: [base])
  httptests.get_raw(output: %w[httptestid], httptestids: [base], selectSteps: 'count')
  httptests.all

  # update, skipped: retries already carries the server's documented default, so only the dump goes out
  httptests.update(httptestid: base, retries: 1)

  # update, issued: two scalars in one request, and the result carries httptestids, plural
  httptests.update(httptestid: base, retries: 3, agent: 'curl')

  # update: steps, which the extend dump lacks, so the update is issued
  httptests.update(httptestid: base, steps: [step(1, 'home'), step(2, 'about')])

  # update, refused: hostid, which the httptest object reference marks constant
  begin
    httptests.update(httptestid: base, hostid: first_host, agent: 'wget')
  rescue ZabbixApi::ApiError
    nil
  end

  # create_or_update, update branch: the lookup is scoped by hostid, the write is not
  httptests.create_or_update(scenario(first_host, Live.name(klass, 'base'), agent: 'upserted'))

  # create_or_update, create branch: no scenario of that name on this host
  httptests.create_or_update(scenario(first_host, Live.name(klass, 'upserted')))

  # get_or_create, found branch: returns the existing id and creates nothing
  httptests.get_or_create(scenario(first_host, Live.name(klass, 'base')))

  # get_or_create, create branch: keeps the hostid, which httptest.create requires
  httptests.get_or_create(scenario(first_host, Live.name(klass, 'gotten')))

  # the two writing aliases
  added = httptests.add(scenario(first_host, Live.name(klass, 'added')))
  httptests.destroy(added)

  # delete with an Integer id and with a String id, for the type the server echoes in each case
  disposable = httptests.create(scenario(first_host, Live.name(klass, 'disposable')))
  httptests.delete(disposable)
  spare = httptests.create(scenario(first_host, Live.name(klass, 'spare')))
  httptests.delete(spare.to_s)

  # delete, refused: no scenario carries that id
  begin
    httptests.delete(999999999)
  rescue ZabbixApi::ApiError
    nil
  end

  Live::Recorder.write(klass, 'crud')
ensure
  Live.teardown
end
