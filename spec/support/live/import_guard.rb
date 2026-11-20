require 'json'

module Live
  # The import interlock for Configurations. configuration.import rewrites objects it was never
  # given the id of - by uuid and by name, from the blob - so the invariant is: no blob handed to
  # import may name an object this spec does not own. Three layers: provenance (exported or authored
  # here), content (no foreign name, every top-level name prefixed), pre-flight (importcompare on
  # the identical payload).
  module ImportGuard
    FOREIGN = [
      Live::PROXY_NAME, Live::GROUP_NAME, Live::TEMPLATE_NAME, *Live::AGENT_HOSTS,
      'Zabbix server', 'Zabbix servers', 'Templates', 'Applications', 'Discovered hosts', 'Email', 'Local network'
    ].freeze

    @registry = {}

    class << self
      def register(source, label, stock: false)
        @registry[source.to_s] = { label: label, stock: stock }
        source
      end

      def export(options, format: 'json', stock: false, prettyprint: nil)
        payload = { format: format, options: options }
        payload[:prettyprint] = prettyprint unless prettyprint.nil?
        blob = Live.retrying('configuration.export') { Live.session.configurations.export(payload) }
        register(blob, "export #{format} of #{options.inspect}", stock: stock)
      end

      def authored(source, label)
        register(source, "authored: #{label}")
      end

      def provenance(source)
        @registry[source.to_s]
      end

      def foreign(text)
        FOREIGN.select { |name| text.to_s.include?(name) }
      end

      # The top-level names a JSON blob carries: what an import can create or overwrite at top level,
      # plus the group and template references it resolves by name. [] for a blob that is not JSON.
      def json_names(source)
        root = JSON.parse(source.to_s)['zabbix_export']
        return [] unless root.is_a?(Hash)

        names = []
        %w[template_groups host_groups media_types maps images].each { |key| Array(root[key]).each { |item| names << item['name'] } }
        Array(root['templates']).each do |template|
          names << template['template'] << template['name']
          Array(template['groups']).each { |group| names << group['name'] }
          Array(template['templates']).each { |link| names << link['name'] }
        end
        Array(root['hosts']).each do |host|
          names << host['host'] << host['name']
          Array(host['groups']).each { |group| names << group['name'] }
          Array(host['templates']).each { |link| names << link['name'] }
        end
        names.compact.reject(&:empty?).uniq
      rescue JSON::ParserError
        []
      end

      def check!(source, label, prefix)
        known = provenance(source)
        raise "import guard: #{label} carries a blob this spec neither exported nor authored" if known.nil?
        raise "import guard: #{label} carries the read-only blob [#{known[:label]}]" if known[:stock]

        strangers = foreign(source)
        raise "import guard: #{label} names #{strangers.join(', ')}" unless strangers.empty?

        stray = json_names(source).reject { |name| name.start_with?(prefix) }
        raise "import guard: #{label} carries the non-spec name(s) #{stray.join(', ')}" unless stray.empty?

        true
      end

      def preflight!(payload, label)
        diff = Live.retrying('configuration.importcompare') { Live.session.configurations.importcompare(payload) }
        strangers = foreign(JSON.generate(diff))
        raise "import guard: the importcompare diff for #{label} names #{strangers.join(', ')}" unless strangers.empty?

        diff
      end

      # The only route to configuration.import. Returns [result, diff]; preflight: false is for the
      # refusal probes, whose payload importcompare refuses first. All three calls here go through
      # the wrapper and are retried, the import without a recheck: a second import of the same
      # template blob, under the rules of each accepted import of the Configurations spec and
      # recorder, leaves the server as the first left it and answers true again, but where the
      # templates rule has createMissing without updateExisting it is refused with Template "<name>"
      # already exists.
      def import!(payload, label, prefix: Live.prefix('configurations'), preflight: true)
        check!(payload[:source], label, prefix)
        diff = preflight ? preflight!(payload, label) : nil
        [Live.retrying('configuration.import') { Live.session.configurations.import(payload) }, diff]
      end
    end
  end
end
