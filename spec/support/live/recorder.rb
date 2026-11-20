require 'fileutils'
require 'json'
require 'tempfile'
require 'time'

module Live
  # Records every exchange of the gem's own client - the request as sent and the parsed answer or
  # error - by wrapping Client#_request, the single place where the two meet. Secrets are scrubbed
  # and one JSON document is written per scenario. A transient database error is the one answer
  # left out: the hook raises it as Transient, so the run aborts instead of keeping a bogus refusal.
  module Recorder
    SCRUB = (ZabbixApi::Client::SECRET_KEYS + %w[auth]).freeze

    @exchanges = []

    class << self
      attr_reader :exchanges

      def start!
        ZabbixApi::Client.prepend(Hook) unless ZabbixApi::Client.ancestors.include?(Hook)
        @exchanges.clear
      end

      def record(request, result: nil, error: nil)
        exchange = { 'n' => @exchanges.size + 1, 'method' => request['method'], 'params' => request['params'] }
        if error.nil?
          exchange['result'] = request['method'] == 'user.login' ? '<scrubbed>' : result
        else
          exchange['error'] = error
        end
        @exchanges << scrub(exchange)
      end

      def scrub(value)
        case value
        when Hash then value.to_h { |key, item| [key, SCRUB.include?(key.to_s) ? '<scrubbed>' : scrub(item)] }
        when Array then value.map { |item| scrub(item) }
        else value
        end
      end

      def write(klass, scenario)
        document = {
          'class' => klass,
          'scenario' => scenario,
          'recorded_at' => Time.now.utc.iso8601,
          'server' => Live.session.server.version,
          'exchanges' => @exchanges
        }
        path = target(klass, scenario)
        File.write(path, "#{JSON.pretty_generate(document)}\n")
        puts "recorded #{@exchanges.size} exchanges to #{path}"
        path
      end

    private

      # Into spec/fixtures/<class>/ by default; with ZABBIX_SPEC_STAGE set, into a random-suffix
      # file directly in /tmp instead, so a recording can be compared with the committed fixture
      # before it replaces it.
      def target(klass, scenario)
        if ENV['ZABBIX_SPEC_STAGE']
          file = Tempfile.create(["#{klass}-#{scenario}-", '.json'], '/tmp')
          file.close
          file.path
        else
          dir = File.join(Fixtures::ROOT, klass)
          FileUtils.mkdir_p(dir)
          File.join(dir, "#{scenario}.json")
        end
      end
    end

    # A transient database error raised by a recorded call. Deliberately not an ApiError: every
    # recorder swallows ApiError around the refusals it records, and a transient swallowed there
    # would land in the fixture as a refusal the server never made. As a class of its own it aborts
    # the run, which the recorder's ensure tears down, while Live.retrying, which matches the
    # message rather than the class, still retries the setup calls it wraps.
    class Transient < StandardError
    end

    module Hook
      def _request(body, auth_required = true)
        request = JSON.parse(body)
        result = super
        Recorder.record(request, result: result)
        result
      rescue ZabbixApi::ApiError => e
        raise Transient.new(e.message) if Live::TRANSIENT.match?(e.message.to_s)

        Recorder.record(request, error: e.response && e.response['error'])
        raise
      end
    end
  end
end
