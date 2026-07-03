require 'spec_helper'

describe 'ZabbixApi::Triggers' do
  let(:triggers_mock) { ZabbixApi::Triggers.new(client) }
  let(:client) { double }

  describe '.method_name' do
    subject { triggers_mock.method_name }

    it { is_expected.to eq 'trigger' }
  end

  describe '.identify' do
    subject { triggers_mock.identify }

    it { is_expected.to eq 'description' }
  end

  describe '.dump_by_id' do
    subject { triggers_mock.dump_by_id(data) }

    let(:data) { { testkey: 222 } }
    let(:result) { { test: 1 } }
    let(:key) { 'testkey' }

    before do
      allow(triggers_mock).to receive(:log)
      allow(triggers_mock).to receive(:key).and_return(key)
      allow(client).to receive(:api_request).with(
        method: 'trigger.get',
        params: {
          filter: {
            key.to_sym => data[key.to_sym]
          },
          output: 'extend',
          selectItems: 'extend',
          selectFunctions: 'extend'
        }
      ).and_return(result)
    end

    it 'logs debug message' do
      expect(triggers_mock).to receive(:log).with("[DEBUG] Call dump_by_id with parameters: #{data.inspect}")
      subject
    end

    it { is_expected.to eq result }
  end

  describe '.safe_update' do
    subject { triggers_mock.safe_update(data) }

    let(:data) { { test: '1', triggerid: 7878, templateid: 4646, expression: '{11a:{22:.33(44)}' } }
    let(:id_hash) { [{ 'test' => 1 }, { 'test2' => 2 }] }
    let(:dump) do
      {
        test: '1',
        triggerid: 7878,
        items: [{ key_: '' }],
        functions: [{ function: '33', parameter: '44' }],
        expression: '{11}'
      }
    end
    let(:hash_equals) { true }
    let(:operation_name) { 'update' }
    let(:key) { 'test' }
    let(:result) { 'rtest' }
    let(:newly_created_item_id) { 1212 }
    let(:method_name) { 'test_method_name' }
    let(:data_to_create) do
      { test: '1', expression: '{11a:{22:.33(44)}' }
    end

    before do
      allow(triggers_mock).to receive(:dump_by_id).with({ test: '1' }).and_return(id_hash)
      allow(triggers_mock).to receive(:symbolize_keys).with({ 'test' => 1 }).and_return(dump)
      allow(triggers_mock).to receive(:hash_equals?).with(dump, data).and_return(hash_equals)
      allow(triggers_mock).to receive(:key).and_return(key)
      allow(triggers_mock).to receive(:method_name).and_return(method_name)
      allow(triggers_mock).to receive(:log)
      allow(triggers_mock).to receive(:create).with(data_to_create).and_return(newly_created_item_id)
      allow(client).to receive(:api_request).with(
        method: "#{method_name}.update",
        params: {
          triggerid: data[:triggerid],
          status: 1
        }
      ).and_return(result)
    end

    it 'logs debug message' do
      expect(triggers_mock).to receive(:log).with("[DEBUG] Call safe_update with parameters: #{data.inspect}")
      subject
    end

    context 'when dump and data hash are equal' do
      it 'logs debug message' do
        expect(triggers_mock).to receive(:log).with('[DEBUG] Equal keys {:test=>"1", :triggerid=>7878, :expression=>"{.33(44)}"} and {:test=>"1", :triggerid=>7878, :expression=>"{.33(44)}"}, skip safe_update')
        expect(triggers_mock).not_to receive(:log).with("[DEBUG] disable : #{result.inspect}")
        subject
      end

      it 'returns item_id' do
        expect(subject).to eq 1
      end
    end

    context 'when dump and data hash are not equal' do
      let(:hash_equals) { false }

      it 'logs debug message' do
        expect(triggers_mock).not_to receive(:log).with(/[DEBUG] Equal keys/)
        expect(triggers_mock).to receive(:log).with('[DEBUG] disable :"rtest"')
        subject
      end

      it 'returns newly created item_id' do
        expect(subject).to eq newly_created_item_id
      end
    end
  end

  describe '.get_or_create' do
    subject { triggers_mock.get_or_create(data) }

    let(:data) { { description: 'testdesc', hostid: 'hostid' } }
    let(:result) { [{ 'testkey' => '111', 'testidentify' => 1 }] }
    let(:key) { 'testkey' }
    let(:identify) { 'testidentify' }
    let(:id) { nil }
    let(:id_through_create) { 222 }

    before do
      allow(triggers_mock).to receive(:log)
      allow(triggers_mock).to receive(:get_id).with(
        description: data[:description],
        hostid: data[:hostid]
      ).and_return(id)
      allow(triggers_mock).to receive(:create).with(data).and_return(id_through_create)
    end

    it 'logs the debug message' do
      expect(triggers_mock).to receive(:log).with("[DEBUG] Call get_or_create with parameters: #{data.inspect}")
      subject
    end

    context 'when ID already exist' do
      let(:id) { '111' }

      it 'returns the existing ID' do
        expect(subject).to eq id
      end
    end

    context 'when id does not exist' do
      it 'returns the newly created ID' do
        expect(subject).to eq id_through_create
      end
    end
  end

  describe '.create_or_update' do
    subject { triggers_mock.create_or_update(data) }

    let(:data) { { description: 'testdesc', hostid: 'hostid' } }

    before do
      allow(triggers_mock).to receive(:log)
      allow(triggers_mock).to receive(:get_or_create)
    end

    it 'logs debug message' do
      expect(triggers_mock).to receive(:log).with("[DEBUG] Call create_or_update with parameters: #{data.inspect}")
      subject
    end

    it 'calls get_or_create function' do
      expect(triggers_mock).to receive(:get_or_create).with(data)
      subject
    end
  end
end
