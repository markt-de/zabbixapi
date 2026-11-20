# Recorder for ZabbixApi::Usermacros: runs the cases below against the server ZABBIX_URL names,
# through the gem itself, and writes spec/fixtures/usermacros/crud.json for the host-macro surface
# and spec/fixtures/usermacros/global.json for the global one. The class is two surfaces over one
# API, so each gets its own file and no exchange has to be guessed at.
#
# The order below is the order the unit spec indexes the files in. crud: the accepted create and
# five refusals, the secret macro, the same macro name on a second host, the reads, three updates
# and a refused one, the four upsert branches, the writing aliases and three deletes. global: the
# accepted create and three refusals, the name the host macro also carries, the reads, the update
# and a refused one, the four upsert branches, one delete and one refused delete.
#
# Not recorded: `all`, which asks for every host macro on the server and would fill the fixture with
# foreign objects; the shared example group drives it from rows of this file instead.
# `get_full_data({})`, whose dropped filter is asserted offline against a scripted exchange for the
# same reason. The bulk array forms, which Usermacros#create, #delete, #create_global and
# #delete_global send as one call through the private request, a path no spec runs on an Array.
#
# The container fixtures - a host group and two hosts - are built before the recording starts: their
# traffic is host traffic, not this class's. Host macros are contents and are not registered for
# teardown, they go with their host. Global macros are server-wide and go with nothing, so each one
# is registered with a deleteglobal deleter for the ensure's teardown.
#
# No recorded call is wrapped in Live.retrying: a retry re-issues every request its block made, so
# a gem call that sends two requests and meets a transient on the second records the first twice.
# A transient database error is raised by the recorder's hook as Live::Recorder::Transient before
# anything is recorded and, being no ApiError, passes the refusal rescues: the run aborts, the
# ensure tears down, and the pre-clean makes a re-run idempotent.
#
# Not a spec - RSpec collects *_spec.rb only - but RuboCop lints it. Run it from the gem's root:
#
#   ZABBIX_URL=<url> ZABBIX_TOKEN=<token> bundle exec ruby spec/recorders/usermacros_recorder.rb
#   ZABBIX_SPEC_STAGE=1 in front writes the files to /tmp instead and prints their paths.
require 'zabbixapi'
require_relative '../support/fixtures'
require_relative '../support/live/live'
require_relative '../support/live/recorder'

# A refusal is one of the cases being recorded - the error exchange is the point - so the run goes on.
def refused
  yield
rescue ZabbixApi::ApiError
  nil
end

klass = 'usermacros'
usermacros = Live.session.usermacros
on_host = Live.macro(klass, 'base')
globally = Live.macro(klass, 'gbase')

# Hosts before their host group; global macros are server-wide and are swept by the uppercase prefix.
Live.preclean(klass, 'host')
Live.preclean(klass, 'hostgroup')
Live.preclean_macros(klass)

group = Live.owns('hostgroup', Live.retrying('group') { Live.session.hostgroups.create(name: Live.name(klass, 'grp')) })
h1 = Live.owns('host', Live.retrying('h1') { Live.session.hosts.create(host: Live.name(klass, 'h1'), groups: [{ groupid: group }]) })
h2 = Live.owns('host', Live.retrying('h2') { Live.session.hosts.create(host: Live.name(klass, 'h2'), groups: [{ groupid: group }]) })

begin
  Live::Recorder.start!

  # create: the accepted minimum
  base = usermacros.create(hostid: h1, macro: on_host, value: 'v1')

  # create, refused: the same macro name twice on one host
  refused { usermacros.create(hostid: h1, macro: on_host, value: 'again') }

  # create, refused: hostid is required
  refused { usermacros.create(macro: Live.macro(klass, 'nohost'), value: 'v') }

  # create, refused: a macro name outside the {$NAME} form
  refused { usermacros.create(hostid: h1, macro: 'not_a_macro', value: 'v') }

  # create, refused: automatic, which the usermacro object reference leaves unmarked in its table
  refused { usermacros.create(hostid: h1, macro: Live.macro(klass, 'auto'), value: 'v', automatic: 1) }

  # create, refused: type is the enum 0, 1, 2
  refused { usermacros.create(hostid: h1, macro: Live.macro(klass, 'badtype'), value: 'v', type: 3) }

  # create: a secret macro, read back below without its value
  secret = usermacros.create(hostid: h1, macro: Live.macro(klass, 'secret'), value: 'zbxapi-spec-usermacros-secret', type: 1)

  # create: the same macro name on a second host, which the server allows
  usermacros.create(hostid: h2, macro: on_host, value: 'v2')

  # the reads
  usermacros.get_id(macro: on_host, hostid: h1)
  usermacros.get_id(macro: Live.macro(klass, 'absent'), hostid: h1)
  usermacros.get_full_data(macro: on_host)
  usermacros.get_full_data(macro: on_host, hostid: h1)
  usermacros.dump_by_id(hostmacroid: base)
  usermacros.dump_by_id(hostmacroid: secret)
  usermacros.get_raw(hostmacroids: [base], output: %w[hostmacroid macro], selectHosts: 'extend')

  # update: issued every time, with no dump read first, and refused for the constant hostid; the
  # update without an id raises in the gem before any request and records nothing
  usermacros.update(hostmacroid: base, value: 'v1-updated')
  usermacros.update(hostmacroid: base, value: 'v1-updated')
  usermacros.update(hostmacroid: base, description: 'recorded by the spec suite')
  refused { usermacros.update(hostmacroid: base, hostid: h1, value: 'moved') }
  refused { usermacros.update(value: 'orphan') }

  # the four host-macro upsert branches
  usermacros.get_or_create(hostid: h1, macro: on_host, value: 'ignored')
  usermacros.get_or_create(hostid: h1, macro: Live.macro(klass, 'goc'), value: 'v')
  usermacros.create_or_update(hostid: h1, macro: on_host, value: 'via-upsert')
  usermacros.create_or_update(hostid: h1, macro: Live.macro(klass, 'cou'), value: 'v')

  # the two writing aliases, and the id types a delete is given
  added = usermacros.add(hostid: h1, macro: Live.macro(klass, 'added'), value: 'v')
  usermacros.destroy(added)
  gone = usermacros.create(hostid: h1, macro: Live.macro(klass, 'gone'), value: 'v')
  usermacros.delete(gone.to_s)
  refused { usermacros.delete(999999999) }

  Live::Recorder.write(klass, 'crud')

  Live::Recorder.start!

  # createglobal: the accepted minimum
  gbase = Live.owns('globalmacro', usermacros.create_global(macro: globally, value: 'g1')) { |id| Live.raw('usermacro.deleteglobal', [id]) }

  # createglobal, refused: the same global macro name twice
  refused { usermacros.create_global(macro: globally, value: 'again') }

  # createglobal, refused: a hostid
  refused { usermacros.create_global(macro: Live.macro(klass, 'ghost'), value: 'g', hostid: h1) }

  # createglobal, refused: value is required
  refused { usermacros.create_global(macro: Live.macro(klass, 'gnoval')) }

  # createglobal: the name the host macro carries too, which the server allows
  Live.owns('globalmacro', usermacros.create_global(macro: on_host, value: 'global-one')) { |id| Live.raw('usermacro.deleteglobal', [id]) }

  # the reads of the global surface
  usermacros.get_id_global(macro: globally)
  usermacros.get_id_global(macro: Live.macro(klass, 'absent'))
  usermacros.get_id_global(macro: on_host, hostid: 999999)
  usermacros.get_full_data_global(macro: globally)
  usermacros.get_raw(globalmacro: true, globalmacroids: [gbase], output: %w[globalmacroid macro])

  # updateglobal: accepted, and refused for a hostid; the update without an id raises in the gem
  # before any request and records nothing
  usermacros.update_global(globalmacroid: gbase, value: 'g1-updated')
  refused { usermacros.update_global(globalmacroid: gbase, hostid: h1, value: 'x') }
  refused { usermacros.update_global(value: 'orphan') }

  # the four global upsert branches, two of them handed a hostid that no recorded request carries
  usermacros.get_or_create_global(macro: globally, value: 'ignored', hostid: h1)
  Live.owns('globalmacro', usermacros.get_or_create_global(macro: Live.macro(klass, 'ggoc'), value: 'gv')) { |id| Live.raw('usermacro.deleteglobal', [id]) }
  usermacros.create_or_update_global(macro: globally, value: 'g-via-upsert', hostid: h1)
  Live.owns('globalmacro', usermacros.create_or_update_global(macro: Live.macro(klass, 'gcou'), value: 'gv')) { |id| Live.raw('usermacro.deleteglobal', [id]) }

  # deleteglobal, accepted and refused
  ggone = Live.owns('globalmacro', usermacros.create_global(macro: Live.macro(klass, 'ggone'), value: 'v')) { |id| Live.raw('usermacro.deleteglobal', [id]) }
  usermacros.delete_global(ggone)
  Live.disown('globalmacro', ggone)
  refused { usermacros.delete_global(999999999) }

  Live::Recorder.write(klass, 'global')
ensure
  Live.teardown
end
