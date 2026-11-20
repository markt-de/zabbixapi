# Recorder for ZabbixApi::Configurations: runs the cases below against the server ZABBIX_URL names,
# through the gem itself, and writes spec/fixtures/configurations/export_import.json.
#
# The fixture set is built before the recording starts, because it is not the subject here: the file
# then holds configuration.* traffic only, and its two importcompare exchanges are the import
# guard's pre-flight. A template group and one template in it are enough for a blob; the acceptance
# spec builds a larger set to assert what an export contains.
#
# The order below is the order the unit spec indexes the file in: the four documented formats and
# prettyprint, four exports the server refuses, the blob the imports use, two imports it accepts
# and three it refuses, and one call per API method the eight inherited entry points reach.
# Not recorded: an import that changes something under createMissing, updateExisting or
# deleteMissing, because it proves the server's behaviour rather than the wrapper's and is the
# acceptance spec's subject.
#
# Every blob handed to import goes through Live::ImportGuard: it is one this run exported, it names
# no standing fixture and none of the stock objects the guard lists, and every top-level name in it
# carries this spec's prefix.
#
# Live.retrying wraps nothing but single-request calls, because a retry re-issues every request
# its block made: a gem call that sends two requests and meets a transient on the second records
# the first twice. Inside the recording those are the import guard's export, importcompare and
# import, one request each, so a transient there is retried and recorded once. On any other
# recorded call the recorder's hook raises a transient as Live::Recorder::Transient before
# anything is recorded and, being no ApiError, it passes the refusal rescues: the run aborts, the
# ensure tears down, and the pre-clean makes a re-run idempotent.
#
# Not a spec - RSpec collects *_spec.rb only - but RuboCop lints it. Run it from the gem's root:
#
#   ZABBIX_URL=<url> ZABBIX_TOKEN=<token> bundle exec ruby spec/recorders/configurations_recorder.rb
#   ZABBIX_SPEC_STAGE=1 in front writes the file to /tmp instead and prints its path.
require 'zabbixapi'
require_relative '../support/fixtures'
require_relative '../support/live/live'
require_relative '../support/live/import_guard'
require_relative '../support/live/recorder'

klass = 'configurations'
configurations = Live.session.configurations

Live.preclean(klass, 'template')
Live.preclean(klass, 'templategroup')

tg_name = Live.name(klass, 'tg')
tg = Live.owns('templategroup', Live.retrying('templategroup.create') { Live.session.templategroups.create(name: tg_name) })
t1_name = Live.name(klass, 't1')
t1 = Live.owns('template', Live.session.templates.create(host: t1_name, name: t1_name, description: 'spec fixture for export and import', groups: [{ groupid: tg }], macros: [{ macro: Live.macro(klass, 'plain'), value: 'plain' }]))
options = { templates: [t1] }

Live::Recorder.start!
begin
  # export: one exchange per documented format, json, xml, yaml and raw, raw answering with an
  # object where the configuration.export reference promises a string
  %w[json xml yaml raw].each { |format| Live::ImportGuard.export(options, format: format) }

  # export: prettyprint travels like every other parameter, the wrapper adds nothing
  Live::ImportGuard.export(options, prettyprint: true)

  # export, refused: format missing, options missing, an unknown format, an unknown options key
  [{ options: options }, { format: 'json' }, { format: 'csv', options: options },
   { format: 'json', options: { hostgroups: [tg] } }].each do |payload|
    configurations.export(payload)
  rescue ZabbixApi::ApiError
    nil
  end

  # the blob every import below carries, exported and registered by the guard
  source = Live::ImportGuard.export(options)

  # import, accepted: the no-op the configuration.import reference documents for no rules, then
  # createMissing and updateExisting for the template group and the template the blob carries, each
  # after a pre-flight importcompare that answers an empty diff
  Live::ImportGuard.import!({ format: 'json', source: source, rules: {} }, 'the no-op import')
  Live::ImportGuard.import!({ format: 'json', source: source, rules: { template_groups: { createMissing: true, updateExisting: true }, templates: { createMissing: true, updateExisting: true } } }, 'the template itself')

  # import, refused: rules missing, the unknown rule key groups, a JSON source declared as xml.
  # preflight: false, because importcompare refuses each of them first and the recording would then
  # hold the wrong method's error.
  [{ format: 'json', source: source },
   { format: 'json', source: source, rules: { groups: { createMissing: true } } },
   { format: 'xml', source: source, rules: { templates: { createMissing: true } } }].each do |payload|
    Live::ImportGuard.import!(payload, 'an import the server refuses', preflight: false)
  rescue ZabbixApi::ApiError
    nil
  end

  # the inherited entry points that reach the wire: one call per API method the server refuses as an
  # incorrect method. create stands for add, delete for destroy, all for get_raw, dump_by_id and
  # update, which all send configuration.get.
  begin
    configurations.create(name: Live.name(klass, 'nothing'))
  rescue ZabbixApi::ApiError
    nil
  end
  begin
    configurations.delete(1)
  rescue ZabbixApi::ApiError
    nil
  end
  begin
    configurations.all
  rescue ZabbixApi::ApiError
    nil
  end

  Live::Recorder.write(klass, 'export_import')
ensure
  Live.teardown
end
