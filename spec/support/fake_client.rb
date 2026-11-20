require 'json'

# Stands in for ZabbixApi::Client in the unit specs. It replays recorded or scripted exchanges by
# method and keeps every request in wire form - string keys, JSON types - so an example asserts
# exactly what the server would have received, while the response is the one the exchange holds,
# with a refusal's quoted secrets masked as Client masks them.
class FakeClient
  class Unexpected < StandardError
  end

  class Mismatch < StandardError
  end

  attr_reader :options, :calls

  def initialize(exchanges = [], debug: false, strict: false)
    @exchanges = wire(exchanges).each { |exchange| exchange['consumed'] = false }
    @options = { debug: debug }
    @strict = strict
    @calls = []
  end

  def api_request(method:, params:)
    request = { 'method' => method, 'params' => wire(params) }
    @calls << request
    exchange = @exchanges.find { |candidate| !candidate['consumed'] && candidate['method'] == method }
    raise Unexpected.new("unexpected #{method} with params #{request['params'].inspect}") if exchange.nil?

    exchange['consumed'] = true
    raise Mismatch.new("#{method} sent #{request['params'].inspect}, the recording has #{exchange['params'].inspect}") if @strict && exchange['params'] != request['params']
    raise api_error(exchange['error'], request) if exchange.key?('error')

    wire(exchange['result'])
  end

  def sent(method)
    @calls.select { |call| call['method'] == method }.map { |call| call['params'] }
  end

  def count(method)
    sent(method).size
  end

  def remaining
    @exchanges.reject { |exchange| exchange['consumed'] }.map { |exchange| exchange.except('consumed') }
  end

private

  # The JSON round trip is the wire form, and a fresh copy every time.
  def wire(value)
    JSON.parse(JSON.generate(value))
  end

  # Built the way Client#_request builds it, so error_message and error read the same: the message
  # shows the request as method and params alone, every params value masked, and response holds the
  # error alone, without the jsonrpc and id of the server's answer; each secret the params carry
  # reads '***' wherever the error quotes it, the longest replaced first.
  def api_error(error, request)
    error = scrub(error, secrets_in(request['params']).sort_by { |secret| -secret.length })
    ZabbixApi::ApiError.new("Server answer API error\n #{JSON.pretty_unparse(error)}\n on request:\n #{JSON.pretty_unparse(request.merge('params' => mask(request['params'])))}", { 'error' => error })
  end

  # Client's masking of a quoted request: every value '***', Hash keys and Array positions kept.
  def mask(value)
    case value
    when Hash then value.transform_values { |item| mask(item) }
    when Array then value.map { |item| mask(item) }
    else '***'
    end
  end

  # Client's secrets of a request, at any depth: every value under a ZabbixApi::Client::SECRET_KEYS
  # name, and the value of a user macro of type 1 in a Hash carrying macro, hostmacroid or
  # globalmacroid, where it is a non-empty String or a Numeric.
  def secrets_in(value)
    case value
    when Hash
      own = value.slice(*ZabbixApi::Client::SECRET_KEYS).values
      own << value['value'] if value['type'].to_s == '1' && value.keys.intersect?(%w[macro hostmacroid globalmacroid])
      own.grep(String).reject(&:empty?) + own.grep(Numeric).map(&:to_s) + value.values.flat_map { |item| secrets_in(item) }
    when Array then value.flat_map { |item| secrets_in(item) }
    else []
    end
  end

  # Client's scrub of an answer: each secret replaced by '***' where a string quotes it.
  def scrub(value, secrets)
    case value
    when Hash then value.transform_values { |item| scrub(item, secrets) }
    when Array then value.map { |item| scrub(item, secrets) }
    when String then secrets.reduce(value) { |text, secret| text.gsub("\"#{secret}\"", '"***"') }
    else value
    end
  end
end
