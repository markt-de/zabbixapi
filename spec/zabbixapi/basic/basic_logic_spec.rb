require 'spec_helper'

describe 'ZabbixApi::Basic' do
  let(:basic_mock) { ZabbixApi::Basic.new(client) }
  let(:client) { double }
  let(:method_name) { 'test-method' }
  let(:default_options) { {} }
  let(:data_create) { [data] }
  let(:result) { 'test-result' }
  let(:method) { "#{method_name}.#{operation_name}" }
  let(:operation_name) { 'dummy' }

  before do
    allow(basic_mock).to receive(:log)
    allow(basic_mock).to receive(:method_name).and_return(method_name)
    allow(basic_mock).to receive(:default_options).and_return(default_options)
    allow(client).to receive(:api_request).with(method: method, params: data_create).and_return(result)
    allow(basic_mock).to receive(:parse_keys)
  end

  describe '.create' do
    subject { basic_mock.create(data) }

    let(:data) { { test: 1 } }
    let(:operation_name) { 'create' }

    it 'logs the debug message' do
      expect(basic_mock).to receive(:log).with("[DEBUG] Call create with parameters: #{data.inspect}")
      subject
    end

    it 'prints the result' do
      expect(basic_mock).to receive(:parse_keys).with(result)
      subject
    end

    context 'when default_options is not empty' do
      let(:default_options) { { test2: 2 } }
      let(:data_create) { [{ test: 1, test2: 2 }] }

      it 'merges data with default options' do
        expect(client).to receive(:api_request)
          .with(method: 'test-method.create', params: data_create)
        subject
      end
    end
  end

  describe '.delete' do
    subject { basic_mock.delete(data) }

    let(:data) { { test: 1 } }
    let(:operation_name) { 'delete' }

    it 'logs the debug message' do
      expect(basic_mock).to receive(:log).with("[DEBUG] Call delete with parameters: #{data.inspect}")
      subject
    end

    it 'prints the result' do
      expect(basic_mock).to receive(:parse_keys).with(result)
      subject
    end
  end

  describe '.create_or_update' do
    subject { basic_mock.create_or_update(data) }

    let(:data) { { test: 1 } }
    let(:identify) { 'test' }
    let(:id) { 1 }

    before do
      allow(basic_mock).to receive(:identify).and_return(identify)
      allow(basic_mock).to receive(:get_id).with(test: 1).and_return(id)
      allow(basic_mock).to receive(:update)
      allow(basic_mock).to receive(:create)
      allow(basic_mock).to receive(:key).and_return('key')
    end

    it 'logs the debug message' do
      expect(basic_mock).to receive(:log).with("[DEBUG] Call create_or_update with parameters: #{data.inspect}")
      subject
    end

    context 'when ID already exists' do
      it 'calls update' do
        expect(basic_mock).to receive(:update).with({ test: 1, key: '1' })
        subject
      end
    end

    context 'when ID does not exist' do
      let(:id) { nil }

      it 'calls create' do
        expect(basic_mock).to receive(:create).with(data)
        subject
      end
    end
  end

  describe '.update' do
    subject { basic_mock.update(data, force) }

    let(:data) { { test: '1' } }
    let(:force) { false }
    let(:id_hash) { [{ 'test' => 1 }, { 'test2' => 2 }] }
    let(:dump) { { test: '1' } }
    let(:hash_equals) { true }
    let(:operation_name) { 'update' }

    before do
      allow(basic_mock).to receive(:dump_by_id).with({ test: '1' }).and_return(id_hash)
      allow(basic_mock).to receive(:symbolize_keys).with({ 'test' => 1 }).and_return({ test: '1' })
      allow(basic_mock).to receive(:hash_equals?).with(dump, data).and_return(hash_equals)
      allow(basic_mock).to receive(:key).and_return('test')
    end

    it 'logs the debug message' do
      expect(basic_mock).to receive(:log).with("[DEBUG] Call update with parameters: #{data.inspect}")
      subject
    end

    context 'when dump and data are equal and force set to false' do
      it 'logs message' do
        expect(basic_mock).to receive(:log).with("[DEBUG] Equal keys #{dump} and #{data}, skip update")
        subject
      end

      it 'returns the integer data value based on key' do
        expect(subject).to eq 1
      end
    end

    context 'when dump and data are equal and force set to true' do
      let(:force) { true }

      it 'parses the result from the api request' do
        expect(basic_mock).to receive(:parse_keys).with(result)
        subject
      end
    end

    context 'when dump and data are not equal and force set to false' do
      let(:hash_equals) { false }

      it 'parses the result from the api request' do
        expect(basic_mock).to receive(:parse_keys).with(result)
        subject
      end
    end
  end

  describe '.get_full_data' do
    subject { basic_mock.get_full_data(data) }

    let(:data) { { testidentify: '1' } }
    let(:result) { [{ result: 'helloworld' }] }
    let(:identify) { 'testidentify' }

    before do
      allow(basic_mock).to receive(:identify).and_return(identify)
      allow(client).to receive(:api_request).with(
        method: "#{method_name}.get",
        params: {
          filter: {
            testidentify: '1'
          },
          output: 'extend'
        }
      ).and_return(result)
    end

    it 'logs the debug message' do
      expect(basic_mock).to receive(:log).with("[DEBUG] Call get_full_data with parameters: #{data.inspect}")
      subject
    end

    context 'when api request is successful' do
      it 'returns an array of hash return by an API' do
        expect(subject).to eq result
      end
    end
  end

  describe '.get_raw' do
    subject { basic_mock.get_raw(data) }

    let(:data) { { testidentify: '1' } }
    let(:result) { [{ result: 'helloworld' }] }
    let(:identify) { 'testidentify' }

    before do
      allow(basic_mock).to receive(:identify).and_return(identify)
      allow(client).to receive(:api_request).with(
        method: "#{method_name}.get",
        params: data
      ).and_return(result)
    end

    it 'logs the debug message' do
      expect(basic_mock).to receive(:log).with("[DEBUG] Call get_raw with parameters: #{data.inspect}")
      subject
    end

    context 'when api request is successful' do
      it 'returns an array of hash return by an API' do
        expect(subject).to eq result
      end
    end
  end

  describe '.dump_by_id' do
    subject { basic_mock.dump_by_id(data) }

    let(:data) { { testkey: '1' } }
    let(:result) { [{ result: 'helloworld' }] }
    let(:key) { 'testkey' }

    before do
      allow(basic_mock).to receive(:key).and_return(key)
      allow(client).to receive(:api_request).with(
        method: "#{method_name}.get",
        params: {
          filter: {
            testkey: '1'
          },
          output: 'extend'
        }
      ).and_return(result)
    end

    it 'logs the debug message' do
      expect(basic_mock).to receive(:log).with("[DEBUG] Call dump_by_id with parameters: #{data.inspect}")
      subject
    end

    context 'when api request is successful' do
      it 'returns an array of hash return by an API' do
        expect(subject).to eq result
      end
    end
  end

  describe '.all' do
    subject { basic_mock.all }

    let(:data) { { testkey: '1' } }
    let(:result) { [{ 'testkey' => '1', 'testidentify' => 2 }] }
    let(:key) { 'testkey' }
    let(:identify) { 'testidentify' }
    let(:expected) { { 2 => '1' } }

    before do
      allow(basic_mock).to receive(:key).and_return(key)
      allow(basic_mock).to receive(:identify).and_return(identify)
      allow(client).to receive(:api_request).with(
        method: "#{method_name}.get",
        params: {
          output: 'extend'
        }
      ).and_return(result)
    end

    context 'when api request is successful' do
      it 'returns an array of hash return by an API' do
        expect(subject).to eq expected
      end
    end
  end

  describe '.get_id' do
    subject { basic_mock.get_id(data) }

    let(:data) { { 'testidentify' => 1 } }
    let(:symbolized_data) { { testidentify: 1 } }
    let(:result) { [{ 'testkey' => '111', 'testidentify' => 1 }] }
    let(:key) { 'testkey' }
    let(:identify) { 'testidentify' }
    let(:id) { 111 }

    before do
      allow(basic_mock).to receive(:key).and_return(key)
      allow(basic_mock).to receive(:identify).and_return(identify)
      allow(basic_mock).to receive(:symbolize_keys).with(data).and_return(symbolized_data)
      allow(client).to receive(:api_request).with(
        method: "#{method_name}.get",
        params: {
          filter: symbolized_data,
          output: [key, identify]
        }
      ).and_return(result)
    end

    it 'logs the debug message' do
      expect(basic_mock).to receive(:log).with("[DEBUG] Call get_id with parameters: #{data.inspect}")
      subject
    end

    context 'when data has `identify` as a key' do
      it 'symbolizes the data' do
        expect(basic_mock).to receive(:symbolize_keys).with(data)
        subject
      end

      it 'returns the id from the response' do
        expect(subject).to eq id
      end
    end

    context 'when data does not have `identify` as a key' do
      let(:identify) { 'wrongtestidentify' }

      it 'symbolizes the data' do
        expect(basic_mock).not_to receive(:symbolize_keys).with(data)
        expect { subject }.to raise_error(ZabbixApi::ApiError, "#{identify} not supplied in call to get_id")
      end
    end
  end

  describe '.get_or_create' do
    subject { basic_mock.get_or_create(data) }

    let(:data) { { testidentify: 1 } }
    let(:result) { [{ 'testkey' => '111', 'testidentify' => 1 }] }
    let(:key) { 'testkey' }
    let(:identify) { 'testidentify' }
    let(:id) { nil }
    let(:id_through_create) { 222 }

    before do
      allow(basic_mock).to receive(:identify).and_return(identify)
      allow(basic_mock).to receive(:get_id).with(testidentify: 1).and_return(id)
      allow(basic_mock).to receive(:create).with(data).and_return(id_through_create)
    end

    it 'logs the debug message' do
      expect(basic_mock).to receive(:log).with("[DEBUG] Call get_or_create with parameters: #{data.inspect}")
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
end
