# Recorder for ZabbixApi::Hosts: runs the cases below against the server ZABBIX_URL names, through
# the gem itself, and writes spec/fixtures/hosts/crud.json.
#
# The order below is the order the unit spec indexes the file in: the accepted minimal create and
# three refusals, the create carrying all six extra parameters, the six reads, the skipped and the
# issued updates including both group reconciliation cases, the refused tag update,
# unlink_templates, the four upsert branches, and the two deletes - through destroy with an Integer
# id and through delete with a String id, host.delete answering with a String for either. Not
# recorded: a forced update, which differs from the skipped one only in being issued and which the
# shared example group proves offline; monitored_by, TLS and the other interface variants, server
# validation of parameters the wrapper only passes through.
#
# unlink_templates is called once, with five keys of which the wrapper forwards hosts_id and
# templates_id alone, so the one exchange carries both the filtered wire shape and the unlink
# itself.
#
# No recorded call is wrapped in Live.retrying: a retry re-issues every request its block made, so
# a gem call that sends two requests and meets a transient on the second records the first twice.
# A transient database error is raised by the recorder's hook as Live::Recorder::Transient before
# anything is recorded and, being no ApiError, passes the refusal rescues: the run aborts, the
# ensure tears down, and the pre-clean makes a re-run idempotent.
#
# Not a spec - RSpec collects *_spec.rb only - but RuboCop lints it. Run it from the gem's root:
#
#   ZABBIX_URL=<url> ZABBIX_TOKEN=<token> bundle exec ruby spec/recorders/hosts_recorder.rb
#   ZABBIX_SPEC_STAGE=1 in front writes the file to /tmp instead and prints its path.
require 'zabbixapi'
require_relative '../support/fixtures'
require_relative '../support/live/live'
require_relative '../support/live/recorder'

klass = 'hosts'
hosts = Live.session.hosts

# Hosts before groups: a group that is a host's only group cannot be deleted.
Live.preclean(klass, 'host')
Live.preclean(klass, 'hostgroup')

# The fixtures the scenario writes into, built before the hook is installed so that the file carries
# host traffic only. The stock template is resolved by name and never written.
group1 = Live.owns('hostgroup', Live.session.hostgroups.create(name: Live.name(klass, 'grp1')))
group2 = Live.owns('hostgroup', Live.session.hostgroups.create(name: Live.name(klass, 'grp2')))
templateid = Live.session.templates.get_id(host: Live::TEMPLATE_NAME)

Live::Recorder.start!
begin
  # create: the accepted minimum, host plus one group
  one = Live.owns('host', hosts.create(host: Live.name(klass, 'one'), groups: [{ groupid: group1 }]))

  # create, refused: groups is required and the injected default sends an empty array
  begin
    hosts.create(host: Live.name(klass, 'nogroups'))
  rescue ZabbixApi::ApiError
    nil
  end

  # create, refused: the unset host placeholder is dropped, so the request carries no host, and the
  # server answers Wrong fields for host ""
  begin
    hosts.create(groups: [{ groupid: group1 }])
  rescue ZabbixApi::ApiError
    nil
  end

  # create, refused: an interface without dns, which the hostinterface object reference requires
  # alongside ip
  begin
    hosts.create(host: Live.name(klass, 'noifdns'), groups: [{ groupid: group1 }],
                 interfaces: [{ type: 1, main: 1, useip: 1, ip: '192.0.2.10', port: '10050' }])
  rescue ZabbixApi::ApiError
    nil
  end

  # create with all six extra parameters at once: groups, interfaces, tags, templates, macros,
  # inventory - the parameters the host.create reference documents on top of the host properties
  full = Live.owns('host', hosts.create(host: Live.name(klass, 'full'), name: 'Full Visible Name',
                                        description: 'spec fixture: every documented create collection',
                                        groups: [{ groupid: group1 }, { groupid: group2 }],
                                        interfaces: [
                                          { type: 1, main: 1, useip: 1, ip: '192.0.2.11', dns: '', port: '10050' },
                                          { type: 2, main: 1, useip: 1, ip: '192.0.2.11', dns: '', port: '161',
                                            details: { version: 2, bulk: 1, community: 'public' } }
                                        ],
                                        tags: [{ tag: 'zbxapi-spec', value: klass }],
                                        templates: [{ templateid: templateid }],
                                        macros: [{ macro: '{$ZBXAPI_SPEC_HOSTS}', value: 'hhh' }],
                                        inventory_mode: 0,
                                        inventory: { location: 'Leipzig', os: 'Linux Debian' }))

  # the reads
  hosts.get_full_data(host: Live.name(klass, 'one'))
  hosts.get_id(host: Live.name(klass, 'one'))
  hosts.get_id(host: Live.name(klass, 'absent'))
  hosts.dump_by_id(hostid: one)
  hosts.get_raw(output: %w[host status], hostids: [one])
  hosts.all

  # update, skipped: the payload already matches the dump, so only the dump goes out
  hosts.update(hostid: one, host: Live.name(klass, 'one'))

  # update, issued: one scalar property
  hosts.update(hostid: one, description: 'desc v1')

  # update, issued: the group set changes, and the reconciliation sorts both sides by groupid
  hosts.update(hostid: one, groups: [{ groupid: group2 }, { groupid: group1 }])

  # update, skipped: the same set in another order and under string keys - only the selectHostGroups
  # of the dump_by_id override makes a group comparison possible at all
  hosts.update(hostid: one, groups: [{ 'groupid' => group1 }, { 'groupid' => group2 }])

  # update, issued: a collection the dump cannot show is never skipped
  hosts.update(hostid: one, interfaces: [{ type: 1, main: 1, useip: 1, ip: '192.0.2.12', dns: '', port: '10050' }])

  # update, refused: automatic is read-only on a host tag
  begin
    hosts.update(hostid: one, tags: [{ tag: 'zbxapi-spec', value: klass, automatic: 1 }])
  rescue ZabbixApi::ApiError
    nil
  end

  # unlink_templates: hosts_id and templates_id reach host.massRemove, the templateids_clear,
  # groupids and macros beside them do not - clearing goes through clear: true instead
  hosts.unlink_templates(hosts_id: [full], templates_id: [templateid], templateids_clear: [templateid],
                         groupids: [group1], macros: ['{$ZBXAPI_SPEC_HOSTS}'])

  # create_or_update, update branch: the host exists, so the id is looked up and merged in as a String
  hosts.create_or_update(host: Live.name(klass, 'one'), description: 'via upsert')

  # create_or_update, create branch, then get_or_create on that same name, which must not create
  Live.owns('host', hosts.create_or_update(host: Live.name(klass, 'two'), groups: [{ groupid: group1 }]))
  hosts.get_or_create(host: Live.name(klass, 'two'))

  # get_or_create, create branch
  Live.owns('host', hosts.get_or_create(host: Live.name(klass, 'three'), groups: [{ groupid: group1 }]))

  # the two writing aliases, and the id type a delete answers for an Integer
  added = Live.owns('host', hosts.add(host: Live.name(klass, 'added'), groups: [{ groupid: group1 }]))
  hosts.destroy(added)
  Live.disown('host', added)

  # delete with a String id, for the type the server answers in that case
  disposable = Live.owns('host', hosts.create(host: Live.name(klass, 'disposable'), groups: [{ groupid: group1 }]))
  hosts.delete(disposable.to_s)
  Live.disown('host', disposable)

  Live::Recorder.write(klass, 'crud')
ensure
  Live.teardown
end
