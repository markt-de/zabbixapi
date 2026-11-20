# Recorder for ZabbixApi::Templates: runs the cases below against the server ZABBIX_URL names,
# through the gem itself, and writes spec/fixtures/templates/crud.json and
# spec/fixtures/templates/mass.json.
#
# Two scenarios, because the mass_* family is a theme of its own and small indices stay readable.
# crud is, in the order the unit spec indexes it: the accepted create and three refusals, the full
# parameter set, the seven reads, the skipped update, the issued one and the collection one, the
# four upsert branches, the three aliases and two deletes, one by an Integer id and one by a String
# id. mass is the three mass_* methods as each works: groups and macros added, replaced and removed,
# a template linked and cleared.
#
# Not recorded: a delete refused while an action references the template, which would need an action
# created here - an action acts on real events once enabled; the bulk array forms, which
# Basic#create and #delete handle and Basic's own spec covers; template groups, which are created
# through the TemplateGroups wrapper before the recording starts, so the fixtures carry template.*
# only; and `all`, whose output: extend answers with every template on the server in one exchange -
# the unit spec replays one recorded row through the shared group instead, and the live spec asserts
# membership rather than the table.
#
# The three mass calls carrying a key the wrapper cannot forward are wrapped in begin/rescue: the
# wrapper refuses each before any request, so they record nothing. No recorded call is wrapped in
# Live.retrying: a retry re-issues every request its block made, so a gem call that sends two
# requests and meets a transient on the second records the first twice. A transient database error
# is raised by the recorder's hook as Live::Recorder::Transient before anything is recorded and,
# being no ApiError, passes the refusal rescues: the run aborts, the ensure tears down, and the
# pre-clean makes a re-run idempotent.
#
# Not a spec - RSpec collects *_spec.rb only - but RuboCop lints it. Run it from the gem's root:
#
#   ZABBIX_URL=<url> ZABBIX_TOKEN=<token> bundle exec ruby spec/recorders/templates_recorder.rb
#   ZABBIX_SPEC_STAGE=1 in front writes the files to /tmp instead and prints their paths.
require 'securerandom'
require 'zabbixapi'
require_relative '../support/fixtures'
require_relative '../support/live/live'
require_relative '../support/live/recorder'

klass = 'templates'
templates = Live.session.templates

# Templates before template groups: a group holding a template that belongs to it alone cannot go.
Live.preclean(klass, 'template')
Live.preclean(klass, 'templategroup')

tg1 = Live.owns('templategroup', Live.retrying('templategroup.create grp1') { Live.session.templategroups.create(name: Live.name(klass, 'grp1')) })
tg2 = Live.owns('templategroup', Live.retrying('templategroup.create grp2') { Live.session.templategroups.create(name: Live.name(klass, 'grp2')) })

# A third template for the links in the mass scenario: `full` is created with `one` as a parent, so
# linking it back into `one` is circular and the server refuses it. Created before Recorder.start!,
# so neither fixture carries its create.
link = Live.owns('template', Live.retrying('template.create link') { templates.create(host: Live.name(klass, 'link'), groups: [{ groupid: tg1 }]) })

Live::Recorder.start!
begin
  # create: the accepted minimum - the technical name and the required template groups
  one = Live.owns('template', templates.create(host: Live.name(klass, 'one'), groups: [{ groupid: tg1 }]))

  # create, refused: the technical name is taken
  begin
    templates.create(host: Live.name(klass, 'one'), groups: [{ groupid: tg1 }])
  rescue ZabbixApi::ApiError
    nil
  end

  # create, refused: the required groups are missing
  begin
    templates.create(host: Live.name(klass, 'nogroups'))
  rescue ZabbixApi::ApiError
    nil
  end

  # create, refused: on create the vendor pair is both or neither
  begin
    templates.create(host: Live.name(klass, 'vendor'), groups: [{ groupid: tg1 }], vendor_name: 'markt.de')
  rescue ZabbixApi::ApiError
    nil
  end

  # create: every documented property and every extra create parameter, the template link included
  full = Live.owns('template', templates.create(host: Live.name(klass, 'full'), name: Live.name(klass, 'full', 'visible'),
                                                description: 'spec fixture', uuid: SecureRandom.uuid.delete('-'),
                                                vendor_name: 'markt.de', vendor_version: '1.0',
                                                groups: [{ groupid: tg1 }, { groupid: tg2 }],
                                                tags: [{ tag: 'zbxapi-spec', value: klass }],
                                                macros: [{ macro: Live.macro(klass, 'a'), value: 'aaa' }],
                                                templates: [{ templateid: one }]))

  # the reads
  templates.get_full_data(host: Live.name(klass, 'one'))
  templates.get_id(host: Live.name(klass, 'one'))
  templates.get_id(host: Live.name(klass, 'absent'))
  templates.dump_by_id(templateid: one)
  templates.get_raw(output: ['host'], templateids: [one], selectTemplateGroups: %w[groupid])
  templates.get_ids_by_host(host: Live.name(klass, 'one'))
  templates.get_ids_by_host(templateids: [one])

  # update, skipped: the payload already matches the dump, so only the dump goes out
  templates.update(templateid: one, host: Live.name(klass, 'one'))

  # update, issued: two properties in one request
  templates.update(templateid: one, description: 'desc v1', name: Live.name(klass, 'one', 'visible'))

  # update, issued for a macros payload: the extend dump carries no macros to compare it with
  templates.update(templateid: one, macros: [{ macro: Live.macro(klass, 'b'), value: 'bbb' }])

  # create_or_update, update branch: the technical name exists, so get_id, dump_by_id and update go out
  templates.create_or_update(host: Live.name(klass, 'one'), description: 'via create_or_update')

  # create_or_update, create branch, then get_or_create on that same name, which finds it and
  # creates nothing
  Live.owns('template', templates.create_or_update(host: Live.name(klass, 'viacou'), groups: [{ groupid: tg1 }]))
  templates.get_or_create(host: Live.name(klass, 'viacou'))

  # get_or_create, create branch
  Live.owns('template', templates.get_or_create(host: Live.name(klass, 'gotten'), groups: [{ groupid: tg1 }]))

  # the three aliases: get reads, add creates, destroy deletes
  templates.get(host: Live.name(klass, 'one'))
  added = Live.owns('template', templates.add(host: Live.name(klass, 'added'), groups: [{ groupid: tg1 }]))
  templates.destroy(added)
  Live.disown('template', added)

  # delete by an Integer id and by a String one; template.delete answers String ids to both
  disposable = Live.owns('template', templates.create(host: Live.name(klass, 'disposable'), groups: [{ groupid: tg1 }]))
  templates.delete(disposable)
  Live.disown('template', disposable)
  stringly = Live.owns('template', templates.create(host: Live.name(klass, 'stringly'), groups: [{ groupid: tg1 }]))
  templates.delete(stringly.to_s)
  Live.disown('template', stringly)

  Live::Recorder.write(klass, 'crud')

  # The mass_* family on its own: what each method forwards
  Live::Recorder.start!

  templates.mass_add(templates_id: [one], groups_id: [tg2], macros: [{ macro: Live.macro(klass, 'c'), value: 'ccc' }])
  # templates_link_id reaches the wire as templates_link, and templates_clear_id takes the link
  # back out again; the raw API spellings below are refused before any request and record nothing.
  templates.mass_add(templates_id: [one], templates_link_id: [link])
  templates.mass_remove(templates_id: [one], templates_clear_id: [link])
  begin
    templates.mass_add(templates_id: [one], templates_link: [{ templateid: full }])
  rescue ZabbixApi::ApiError
    nil
  end

  templates.mass_update(templates_id: [one], groups_id: [tg1], macros: [{ macro: Live.macro(klass, 'd'), value: 'ddd' }])
  begin
    templates.mass_update(templates_id: [one], templates_clear: [{ templateid: full }])
  rescue ZabbixApi::ApiError
    nil
  end

  # back into both groups, so the removal below has something to remove
  templates.mass_add(templates_id: [one], groups_id: [tg2])
  templates.mass_remove(templates_id: [one], groups_id: [tg2])
  begin
    templates.mass_remove(templates_id: [one], group_id: tg1)
  rescue ZabbixApi::ApiError
    nil
  end
  templates.mass_remove(templates_id: [one], macros: [Live.macro(klass, 'd')])

  Live::Recorder.write(klass, 'mass')
ensure
  Live.teardown
end
