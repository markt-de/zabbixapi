# Contract: ZabbixApi::Server
#   classes:  not a Basic subclass and carries none of its surface | one instance method, no writer
#             | version is what the client's api_version answered, that object and not a copy |
#             the client is asked once, at construction, however often version is read | the class
#             issues no request of its own | a value the client's gate would have refused passes
#             through unvalidated | snapshot: an existing Server keeps its value where one built
#             later takes the client's current | a client-less construction raises instead of
#             yielding a nil version
#   not here: that the version is the one the running server answers, and that the facade memoises
#             one Server per connection - spec/acceptance/server_spec.rb measures both live; that
#             Server#version equals the client's memoised api_version on a real connection, which
#             spec/acceptance/client_spec.rb owns; the memoisation of Client#api_version itself,
#             the version gate and the empty array apiinfo.version is called with, all
#             spec/zabbixapi/client_spec.rb's subject; a recorded fixture, because the one
#             collaborator call this class makes is Client#api_version, which FakeClient does not
#             answer and a recording therefore cannot carry
require 'spec_helper'

RSpec.describe ZabbixApi::Server do
  version = '7.0.30'
  # The CRUD methods, aliases and hooks Basic gives its subclasses. Server is not one of them, so
  # none of these may answer here.
  basic_surface = [:create, :delete, :update, :create_or_update, :get_or_create, :get_full_data, :get_raw, :dump_by_id, :all, :get_id, :get, :add, :destroy, :method_name, :identify, :key, :keys, :default_options]

  let(:client) { instance_double(ZabbixApi::Client, api_version: version) }

  subject(:server) { described_class.new(client) }

  describe 'the class design' do
    it 'stands outside the Basic hierarchy' do
      expect(described_class.superclass).to eq(Object)
      expect(described_class.ancestors).not_to include(ZabbixApi::Basic)
    end

    it 'defines version alone, and no writer for it' do
      expect(described_class.instance_methods(false)).to eq([:version])
      expect(server).not_to respond_to(:version=)
    end

    it 'answers to none of the resource surface Basic gives the other classes' do
      expect(basic_surface.select { |method| server.respond_to?(method) }).to eq([])
    end
  end

  describe '#version' do
    it 'is what the client answered, that string itself rather than a copy or a reformatting' do
      expect(server.version).to equal(version)
    end

    it 'asks the client once over five reads' do
      5.times { server.version }

      expect(client).to have_received(:api_version).once
    end

    it 'issues no request of its own' do
      allow(client).to receive(:api_request)
      described_class.new(client).version

      expect(client).not_to have_received(:api_request)
    end

    it 'hands through a version the client gate would have refused' do
      unsupported = instance_double(ZabbixApi::Client, api_version: '6.4.0')

      expect(described_class.new(unsupported).version).to eq('6.4.0')
    end
  end

  describe 'snapshot semantics' do
    it "reports the client's first answer, where a Server built after it reports the next one" do
      moving = instance_double(ZabbixApi::Client)
      allow(moving).to receive(:api_version).and_return(version, '9.9.9')

      first = described_class.new(moving)
      second = described_class.new(moving)
      expect([first.version, second.version]).to eq([version, '9.9.9'])
    end
  end

  describe 'construction without a client' do
    it 'raises rather than yielding a Server whose version is nil' do
      expect { described_class.new(nil) }.to raise_error(NoMethodError, /api_version/)
    end
  end
end
