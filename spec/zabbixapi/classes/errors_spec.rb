# Contract: ZabbixApi::BaseError, ZabbixApi::ApiError, ZabbixApi::HttpError, ZabbixApi::TransportError
#   classes:  the hierarchy, and that no subclass adds a method of its own | an error body fills
#             response, error and error_message | the body is read and never written | an error
#             object without data still joins | a message alone leaves all three nil, the shape
#             every local guard raises | a response with no usable error object, reached three ways:
#             the property missing, indexing raising, the property malformed | HttpError keeps the
#             HTTP response and has no detail to offer | TransportError carries a message alone and
#             keeps the stdlib original as cause | all three accessors are writable | as a request
#             path raises it: the message opens with "Server answer API error" and quotes the reason
#             JSON-escaped, error_message carries it unescaped
#   not here: which method raises which error, the subject of each class's own spec; the redaction
#             of the quoted request, the secrets a refusal quotes back masked in the message and the
#             accessors, the status inside an HttpError message, the version gate and which stdlib
#             failures become a TransportError, all five spec/zabbixapi/client_spec.rb's; the live
#             refusal, the wrong path, the dead port and the passphrase a refusal quotes back, which
#             spec/acceptance/client_spec.rb measures - the error classes have no live surface of
#             their own, so they have neither an acceptance spec nor a recorded fixture
require 'spec_helper'

RSpec.describe ZabbixApi::BaseError do
  # The error object exactly as the manual's API page documents it under "Error handling": a code, a
  # short error summary in message, the reason in data, and quotes inside that reason.
  refusal = { 'code' => -32602, 'message' => 'Invalid params.', 'data' => 'No groups for host "Linux server".' }.freeze
  # What Client#_request hands the constructor: the whole parsed body, the error object inside it.
  body = { 'jsonrpc' => '2.0', 'error' => refusal, 'id' => 7 }.freeze

  # The exception a call raised, so that its accessors can be asserted one per line.
  def raised
    yield
    raise 'the call was answered, not refused'
  rescue ZabbixApi::BaseError => e
    e
  end

  describe 'the hierarchy' do
    it 'descends from RuntimeError, so an ordinary rescue catches it' do
      caught = begin
        raise described_class.new('boom')
      rescue StandardError => e
        e
      end

      expect(described_class.superclass).to eq(RuntimeError)
      expect(caught.message).to eq('boom')
    end

    it 'is what ApiError, HttpError and TransportError descend from, and none of them adds a method of its own' do
      expect([ZabbixApi::ApiError.superclass, ZabbixApi::HttpError.superclass, ZabbixApi::TransportError.superclass]).to eq([described_class, described_class, described_class])
      expect(ZabbixApi::ApiError.instance_methods(false) + ZabbixApi::HttpError.instance_methods(false) + ZabbixApi::TransportError.instance_methods(false)).to be_empty
    end

    it 'catches all three kinds in one rescue clause, while an ApiError is no HttpError and a TransportError no ApiError' do
      expect { raise ZabbixApi::ApiError.new('refused') }.to raise_error(described_class, 'refused')
      expect { raise ZabbixApi::HttpError.new('not found') }.to raise_error(described_class, 'not found')
      expect { raise ZabbixApi::TransportError.new('connection refused') }.to raise_error(described_class, 'connection refused')
      expect(ZabbixApi::ApiError.new('refused')).not_to be_a(ZabbixApi::HttpError)
      expect(ZabbixApi::TransportError.new('connection refused')).not_to be_a(ZabbixApi::ApiError)
    end
  end

  describe 'built with a response that carries an error object' do
    it 'keeps the parsed body on response, the error object on error, and message and data joined on error_message' do
      error = described_class.new('Server answer API error', body)

      expect(error.response).to be(body)
      expect(error.error).to be(refusal)
      expect(error.error_message).to eq('Invalid params.: No groups for host "Linux server".')
    end

    it 'accepts a frozen body and its frozen error object' do
      expect([body.frozen?, body['error'].frozen?]).to eq([true, true])
      expect { described_class.new('Server answer API error', body) }.not_to raise_error
    end

    it 'joins the two halves even when the error object carries no data' do
      # This is what the formula does when data is absent, not a claim about the server.
      error = described_class.new('boom', 'error' => { 'code' => -32600, 'message' => 'Invalid Request.' })

      expect(error.error_message).to eq('Invalid Request.: ')
    end
  end

  describe 'built with a message alone, the shape every local guard raises' do
    it 'keeps the message and leaves response, error and error_message nil' do
      error = ZabbixApi::ApiError.new('groupid not supplied in call to dump_by_id')

      expect(error.message).to eq('groupid not supplied in call to dump_by_id')
      expect([error.response, error.error, error.error_message]).to eq([nil, nil, nil])
    end
  end

  describe 'built with a response that carries no usable error object' do
    it 'keeps the response and reports no detail when the body has no error property' do
      answer = { 'jsonrpc' => '2.0', 'result' => [], 'id' => 7 }
      error = described_class.new('boom', answer)

      expect(error.response).to be(answer)
      expect([error.error, error.error_message]).to eq([nil, nil])
    end

    it 'keeps the response and reports no detail when indexing it by name raises instead of answering nil' do
      error = described_class.new('boom', %w[not a body])

      expect(error.response).to eq(%w[not a body])
      expect([error.error, error.error_message]).to eq([nil, nil])
    end

    it 'leaves no half-derived error behind when the property is there but the message cannot be built from it' do
      error = described_class.new('boom', 'error' => [])

      expect([error.error, error.error_message]).to eq([nil, nil])
    end
  end

  describe 'the accessors' do
    it 'are writable, so a caller can overwrite what the constructor derived' do
      error = described_class.new('Server answer API error', body)

      error.response = nil
      error.error = nil
      error.error_message = 'rewritten'

      expect([error.response, error.error, error.error_message]).to eq([nil, nil, 'rewritten'])
    end
  end

  describe ZabbixApi::HttpError do
    it 'keeps the HTTP response itself, which is no parsed body and carries no detail to report' do
      response = instance_double(Net::HTTPResponse, code: '404', body: 'Not Found', :[] => nil)
      error = described_class.new('HTTP Error: 404 on http://zabbix.example.invalid/api_jsonrpc.php', response)

      expect(error.response).to be(response)
      expect(error.response.code).to eq('404')
      expect([error.error, error.error_message]).to eq([nil, nil])
    end
  end

  describe ZabbixApi::TransportError do
    it 'carries a message alone, keeps the stdlib original as cause and offers no detail' do
      error = raised do
        raise Errno::ECONNREFUSED
      rescue SystemCallError => e
        raise described_class.new("Transport error on http://zabbix.example.invalid/api_jsonrpc.php: #{e.class}: #{e.message}")
      end

      expect(error.cause).to be_a(Errno::ECONNREFUSED)
      expect([error.response, error.error, error.error_message]).to eq([nil, nil, nil])
    end
  end

  describe ZabbixApi::ApiError do
    # FakeClient raises it the way Client#_request does (spec/support/fake_client.rb), so these two
    # read the shape a request path really produces, without opening a socket.
    let(:client) { FakeClient.new([{ method: 'host.create', error: refusal }]) }
    let(:error) { raised { client.api_request(method: 'host.create', params: [{ host: 'Linux server' }]) } }

    it "reaches the caller as an ApiError whose message opens with \"Server answer API error\" and whose error_message joins the server's message and data, for a host without groups" do
      expect(error).to be_a(described_class)
      expect(error.message.lines.first.chomp).to eq('Server answer API error')
      expect(error.error_message).to eq('Invalid params.: No groups for host "Linux server".')
    end

    it 'quotes the reason JSON-escaped inside the message and unescaped on error_message' do
      expect(error.message).to include('No groups for host \"Linux server\"')
      expect(error.message).not_to include('No groups for host "Linux server"')
      expect(error.error_message).to include('No groups for host "Linux server"')
      expect(error.error).to eq(refusal)
    end
  end
end
