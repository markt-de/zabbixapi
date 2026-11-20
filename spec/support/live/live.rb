require 'json'

# The live layer of the acceptance specs and the recorders: the server state they need, one
# connection to the server ZABBIX_URL names, the retry of a lost or failed connection, raw reads,
# the per-class prefix, the created-object registry with its fixpoint teardown, the own-prefix
# pre-clean of containers, the bounded wait. The other files under support/live/ reopen this module.
module Live
  class Timeout < StandardError
  end

  PREFIX = 'zbxapi-spec'.freeze

  # The server state the acceptance specs and the recorders need: the version the fixtures were
  # recorded against; global script execution enabled on the Zabbix server, which a new 7.0
  # installation's server configuration disables (EnableGlobalScripts); a Super admin's token; the
  # stock objects and settings they rely on - those a Zabbix 7.0 installation ships with - as
  # shipped, Admin's default password and the default password policy included; no action enabled;
  # every problem present when a spec starts unchanged when it ends; and the standing proxy and
  # hosts below, read by name and never written.
  #
  # The standing proxy, in no proxy group.
  PROXY_NAME = 'zabbix-proxy-sqlite3'.freeze
  # A stock host group.
  GROUP_NAME = 'Linux servers'.freeze
  # A stock template, linkable to a host without an interface.
  TEMPLATE_NAME = 'Linux by Zabbix agent active'.freeze
  # The standing hosts, none with an interface.
  AGENT_HOSTS = %w[agent11 agent12 agent21 agent22].freeze
  # The standing hosts the standing proxy monitors.
  PROXIED_HOSTS = %w[agent12 agent22].freeze
  # The stock host carrying the standing problem: a problem never updated through event.acknowledge,
  # whose name no other problem carries.
  STANDING_PROBLEM_HOST = 'Zabbix server'.freeze

  # The only errors retried: those reporting a lost or failed connection, to the server or from the
  # server to its database.
  TRANSIENT = /Error connecting to database|database is not available|Connection to the database|Lost connection|Connection reset|Broken pipe|execution expired/i
  TRIES = 5
  DELAY = 3

  # Containers a spec may pre-clean by name, with the field the prefix is searched in and the id
  # field. Contents (items, triggers, graphs, web scenarios, value maps, host macros) go with their
  # host and are never swept by name: low-level discovery creates items whose names quote other
  # objects' names, a spec's prefix included.
  CONTAINERS = {
    'host' => %w[host hostid],
    'template' => %w[host templateid],
    'hostgroup' => %w[name groupid],
    'templategroup' => %w[name groupid],
    'proxy' => %w[name proxyid],
    'proxygroup' => %w[name proxy_groupid],
    'maintenance' => %w[name maintenanceid],
    'script' => %w[name scriptid],
    'action' => %w[name actionid],
    'drule' => %w[name druleid],
    'mediatype' => %w[name mediatypeid]
  }.freeze

  @registry = []
  @session = nil

  class << self
    def configured?
      !ENV['ZABBIX_URL'].to_s.empty? && !ENV['ZABBIX_TOKEN'].to_s.empty?
    end

    def url
      ENV.fetch('ZABBIX_URL')
    end

    def token
      ENV.fetch('ZABBIX_TOKEN') { raise 'ZABBIX_TOKEN is not set' }
    end

    def session
      @session ||= retrying('connect') { ZabbixApi.connect(url: url, token: token) }
    end

    def retrying(label, tries: TRIES, delay: DELAY)
      attempt = 0
      loop do
        attempt += 1
        begin
          return yield
        rescue StandardError => e
          raise unless TRANSIENT.match?(e.message.to_s) && attempt < tries

          warn "    [retry #{attempt}/#{tries}] #{label}: #{e.class}"
          sleep delay
        end
      end
    end

    def raw(method, params = {})
      retrying(method) { session.query(method: method, params: params) }
    end

    def get(object, params = {})
      raw("#{object}.get", { output: 'extend' }.merge(params))
    end

    def one(object, params = {})
      get(object, params).first
    end

    def count(object, params = {})
      raw("#{object}.get", params.merge(countOutput: true)).to_i
    end

    def prefix(klass)
      "#{PREFIX}-#{klass}"
    end

    def name(klass, *parts)
      ([prefix(klass)] + parts.map(&:to_s)).join('-')
    end

    def macro_prefix(klass)
      "{$#{prefix(klass).upcase.tr('-', '_')}"
    end

    def macro(klass, *parts)
      "#{([macro_prefix(klass)] + parts.map { |part| part.to_s.upcase.tr('-', '_') }).join('_')}}"
    end

    def owns(object, id, &deleter)
      @registry << [object, id, deleter || ->(target) { raw("#{object}.delete", [target]) }]
      id
    end

    def disown(object, id)
      @registry.reject! { |entry| entry[0] == object && entry[1] == id }
      id
    end

    # Reverse creation order is a good first guess and not always right (a proxy created after a
    # host it monitors can only go after that host), so passes repeat until nothing more can be
    # removed.
    def teardown
      remaining = @registry.reverse
      until remaining.empty?
        failed = remaining.reject { |entry| remove(entry) }
        break if failed.empty?

        if failed.size == remaining.size
          failed.each { |object, id, _| warn "  [teardown] #{object} #{id} not removed" }
          break
        end
        remaining = failed
      end
      @registry.clear
    end

    def preclean(klass, object)
      field, id_field = CONTAINERS.fetch(object) { raise ArgumentError.new("#{object} is not a container a spec may pre-clean") }
      raw("#{object}.get", output: [id_field, field], search: { field => prefix(klass) }).each do |row|
        next unless row[field].start_with?(prefix(klass))

        retrying("pre-clean #{object}") { raw("#{object}.delete", [row[id_field].to_i]) }
      rescue StandardError => e
        warn "  [pre-clean] #{object} #{row[field]} not removed: #{e.class}"
      end
    end

    def preclean_macros(klass)
      raw('usermacro.get', globalmacro: true, output: %w[globalmacroid macro], search: { macro: macro_prefix(klass) }).each do |row|
        next unless row['macro'].start_with?(macro_prefix(klass))

        retrying('pre-clean global macro') { raw('usermacro.deleteglobal', [row['globalmacroid'].to_i]) }
      rescue StandardError => e
        warn "  [pre-clean] global macro #{row['macro']} not removed: #{e.class}"
      end
    end

    def wait(what, max: 60, step: 2)
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      loop do
        got = yield
        return got if got

        elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
        raise Timeout.new("gave up after #{elapsed.round} s waiting for #{what}") if elapsed >= max

        sleep step
      end
    end

  private

    def remove(entry)
      entry[2].call(entry[1])
      true
    rescue StandardError
      false
    end
  end
end
