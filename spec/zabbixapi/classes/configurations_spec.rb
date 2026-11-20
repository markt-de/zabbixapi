# Contract: ZabbixApi::Configurations
#   evidence: spec/fixtures/configurations/export_import.json;
#             https://www.zabbix.com/documentation/7.0/en/manual/api/reference/configuration
#   classes:  hooks, identify left unset | export forwards the caller's parameters and adds nothing
#             | export returns the server's document untouched: a String for json, xml and yaml, a
#             Hash for raw | import forwards likewise and returns true | importcompare forwards the
#             same three parameters and answers the server's diff | export and import refusals reach
#             error_message | all three own methods send one wire form for either key style and
#             leave the caller's hash alone | the five inherited entry points that raise locally and
#             send nothing | dump_by_id and update refuse to run blind | the eight that do reach the
#             server, each with the request shape Basic gives it, refused as an incorrect method
#   not here: what an export contains and what an import changes - server behaviour, and the
#             acceptance spec's subject; what an importcompare diff holds when something really
#             differs, likewise server behaviour and the acceptance spec's; the shared group 'a
#             Basic resource', which asserts identify as a value where this class's identify raises,
#             so the hooks get their own examples; every group whose examples need an inherited CRUD
#             call to succeed, as none can for an object that does not exist
require 'spec_helper'

RSpec.describe ZabbixApi::Configurations do
  scenario = 'configurations/export_import'
  traffic = Fixtures.exchanges(scenario)

  json_export = Fixtures.exchange(scenario, 'configuration.export', 0)
  xml_export = Fixtures.exchange(scenario, 'configuration.export', 1)
  yaml_export = Fixtures.exchange(scenario, 'configuration.export', 2)
  raw_export = Fixtures.exchange(scenario, 'configuration.export', 3)
  no_format = Fixtures.exchange(scenario, 'configuration.export', 5)
  no_options = Fixtures.exchange(scenario, 'configuration.export', 6)
  unknown_format = Fixtures.exchange(scenario, 'configuration.export', 7)
  unknown_option = Fixtures.exchange(scenario, 'configuration.export', 8)

  accepted_import = Fixtures.exchange(scenario, 'configuration.import', 0)
  rules_import = Fixtures.exchange(scenario, 'configuration.import', 1)
  no_rules = Fixtures.exchange(scenario, 'configuration.import', 2)
  unknown_rule = Fixtures.exchange(scenario, 'configuration.import', 3)
  wrong_source_format = Fixtures.exchange(scenario, 'configuration.import', 4)

  refused_create = Fixtures.exchange(scenario, 'configuration.create')
  refused_delete = Fixtures.exchange(scenario, 'configuration.delete')
  refused_get = Fixtures.exchange(scenario, 'configuration.get')

  # A template id and the blob of the recording, for realistic payloads. The expected requests are
  # spelled out below rather than compared with the recorded params, which would only show the gem
  # sending what it sent when the fixture was recorded.
  templateid = json_export['params']['options']['templates'].first
  source = accepted_import['params']['source']

  let(:client) { FakeClient.new(traffic) }
  let(:configurations) { described_class.new(client) }

  # None of the three own methods normalises its keys, because none reads the hash it is given: it
  # goes straight to the client, where JSON makes both key styles one wire form. The group proves
  # that equality, and that the caller's hash comes back untouched. No inherited entry point can
  # take it: each of them raises before or at the request.
  it_behaves_like 'a key-normalising entry point', method: :export, payload: { format: 'json', options: { templates: [11113] } }, exchanges: Fixtures.exchanges(scenario)
  it_behaves_like 'a key-normalising entry point', method: :import, payload: { format: 'json', source: Fixtures.exchange(scenario, 'configuration.import', 0)['params']['source'], rules: {} }, exchanges: Fixtures.exchanges(scenario)
  it_behaves_like 'a key-normalising entry point', method: :importcompare, payload: { format: 'json', source: Fixtures.exchange(scenario, 'configuration.importcompare', 0)['params']['source'], rules: {} }, exchanges: Fixtures.exchanges(scenario)

  describe 'the hooks' do
    it 'names the API method prefix configuration and derives key and keys from it' do
      expect([configurations.method_name, configurations.key, configurations.keys]).to eq(%w[configuration configurationid configurationids])
    end

    it 'leaves identify unset, so asking for it raises' do
      expect { configurations.identify }.to raise_error(ZabbixApi::ApiError, /Can't call identify here/)
    end

    it 'takes default_options from Basic, empty' do
      expect([configurations.default_options, configurations.method(:default_options).owner]).to eq([{}, ZabbixApi::Basic])
    end

    it 'adds exactly export, import and importcompare to the inherited surface' do
      expect(described_class.public_instance_methods(false) - ZabbixApi::Basic.public_instance_methods).to match_array([:export, :import, :importcompare])
    end
  end

  describe '#export' do
    it 'sends the caller parameters as the request parameters: no wrapping Array, no filter, no output' do
      configurations.export(format: 'json', options: { templates: [templateid] }, prettyprint: true)
      expect(client.sent('configuration.export').last).to eq('format' => 'json', 'options' => { 'templates' => [templateid] }, 'prettyprint' => true)
    end

    it 'returns the serialized document untouched for json, xml and yaml, parsing nothing' do
      [json_export, xml_export, yaml_export].each do |exchange|
        returned = described_class.new(FakeClient.new([exchange])).export(format: exchange['params']['format'], options: { templates: [templateid] })
        expect(returned).to be_a(String)
        expect(returned).to eq(exchange['result'])
      end
    end

    it 'returns a Hash for format raw, where the configuration.export reference promises a string' do
      returned = described_class.new(FakeClient.new([raw_export])).export(format: 'raw', options: { templates: [templateid] })
      expect(returned).to be_a(Hash)
      expect(returned['zabbix_export']['version']).to eq('7.0')
    end

    it 'raises ApiError carrying the server reason in error_message, for a refused export' do
      [
        [no_format, { options: { templates: [templateid] } }, /the parameter "format" is missing/],
        [no_options, { format: 'json' }, /the parameter "options" is missing/],
        [unknown_format, { format: 'csv', options: { templates: [templateid] } }, /value must be one of "yaml", "xml", "json", "raw"/],
        [unknown_option, { format: 'json', options: { hostgroups: [templateid] } }, /unexpected parameter "hostgroups"/]
      ].each do |exchange, payload, reason|
        expect { described_class.new(FakeClient.new([exchange])).export(payload) }
          .to raise_error(ZabbixApi::ApiError) { |error| expect(error.error_message).to match(reason) }
      end
    end
  end

  describe '#import' do
    it 'sends the caller parameters as the request parameters, format, source and rules as given' do
      configurations.import(format: 'json', source: source, rules: {})
      expect(client.sent('configuration.import').last).to eq('format' => 'json', 'source' => source, 'rules' => {})
    end

    it 'returns the boolean the server answers with, not an id, for an empty and for a populated rules object' do
      [accepted_import, rules_import].each do |exchange|
        returned = described_class.new(FakeClient.new([exchange])).import(format: 'json', source: source, rules: exchange['params']['rules'])
        expect(returned).to be(true)
      end
    end

    it 'raises ApiError carrying the server reason in error_message, for a refused import' do
      [
        [no_rules, { format: 'json', source: source }, /the parameter "rules" is missing/],
        [unknown_rule, { format: 'json', source: source, rules: { groups: { createMissing: true } } }, /unexpected parameter "groups"/],
        [wrong_source_format, { format: 'xml', source: source, rules: { templates: { createMissing: true } } }, /Cannot read XML/]
      ].each do |exchange, payload, reason|
        expect { described_class.new(FakeClient.new([exchange])).import(payload) }
          .to raise_error(ZabbixApi::ApiError) { |error| expect(error.error_message).to match(reason) }
      end
    end
  end

  describe '#importcompare' do
    it 'answers the diff the server computed' do
      exchange = Fixtures.exchange(scenario, 'configuration.importcompare', 1)
      answered = described_class.new(FakeClient.new([exchange])).importcompare(format: 'json', source: exchange['params']['source'], rules: exchange['params']['rules'])

      expect(answered).to eq(exchange['result'])
    end

    it 'adds no wrapping Array, no filter and no output' do
      configurations.importcompare(format: 'json', source: 'src', rules: {})
      expect(client.sent('configuration.importcompare').last).to eq('format' => 'json', 'source' => 'src', 'rules' => {})
    end
  end

  describe 'the inherited entry points that never reach the wire' do
    it 'raises on the unset identify and sends nothing, for the four reads and upserts and the get alias' do
      [:get_full_data, :get, :get_id, :get_or_create, :create_or_update].each do |method|
        fake = FakeClient.new
        expect { described_class.new(fake).public_send(method, name: 'anything') }.to raise_error(ZabbixApi::ApiError, /Can't call identify here/)
        expect(fake.calls).to be_empty
      end
    end

    it_behaves_like 'a lookup that refuses to run blind', method: :dump_by_id, field: 'configurationid'

    it 'refuses an update whose payload names no configurationid, through the dump it would have to read first' do
      expect { configurations.update(name: 'anything') }.to raise_error(ZabbixApi::ApiError, /configurationid not supplied in call to dump_by_id/)
      expect(client.calls).to be_empty
    end
  end

  describe 'the inherited entry points that reach the server' do
    it 'sends the request Basic builds and surfaces the incorrect-method refusal' do
      [
        [refused_create, :create, [{ name: 'anything' }], 'configuration.create', [{ 'name' => 'anything' }]],
        [refused_create, :add, [{ name: 'anything' }], 'configuration.create', [{ 'name' => 'anything' }]],
        [refused_delete, :delete, [1], 'configuration.delete', [1]],
        [refused_delete, :destroy, [1], 'configuration.delete', [1]],
        [refused_get, :get_raw, [{}], 'configuration.get', {}],
        [refused_get, :all, [], 'configuration.get', { 'output' => 'extend' }],
        [refused_get, :dump_by_id, [{ configurationid: 1 }], 'configuration.get', { 'filter' => { 'configurationid' => 1 }, 'output' => 'extend' }],
        [refused_get, :update, [{ configurationid: 1 }], 'configuration.get', { 'filter' => { 'configurationid' => 1 }, 'output' => 'extend' }]
      ].each do |exchange, method, args, sent, params|
        fake = FakeClient.new([exchange])
        expect { described_class.new(fake).public_send(method, *args) }
          .to raise_error(ZabbixApi::ApiError) { |error| expect(error.error_message).to match(/Incorrect method "#{Regexp.escape(sent)}"/) }
        expect(fake.sent(sent)).to eq([params])
      end
    end
  end
end
