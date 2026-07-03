require 'spec_helper'

describe 'ZabbixApi::Graphs' do
  let(:graphs_mock) { ZabbixApi::Graphs.new(client) }
  let(:client) { double }

  describe '.method_name' do
    subject { graphs_mock.method_name }

    it { is_expected.to eq 'graph' }
  end

  describe '.identify' do
    subject { graphs_mock.identify }

    it { is_expected.to eq 'name' }
  end

  describe '.get_full_data' do
    subject { graphs_mock.get_full_data(data) }

    let(:data) { { testid: 222 } }
    let(:result) { { test: 1 } }
    let(:identify) { 'testid' }
    let(:method_name) { 'testmethod' }

    before do
      allow(graphs_mock).to receive(:log)
      allow(graphs_mock).to receive(:identify).and_return(identify)
      allow(graphs_mock).to receive(:method_name).and_return(method_name)
      allow(client).to receive(:api_request).with(
        method: "#{method_name}.get",
        params: {
          search: {
            testid: 222
          },
          output: 'extend'
        }
      ).and_return(result)
    end

    it 'logs debug message' do
      expect(graphs_mock).to receive(:log).with("[DEBUG] Call get_full_data with parameters: #{data.inspect}")
      subject
    end

    it { is_expected.to eq result }
  end

  describe '.get_ids_by_host' do
    subject { graphs_mock.get_ids_by_host(data) }

    let(:data) { { host: 'testhost', filter: 'id3' } }
    let(:result) do
      [
        { 'graphid' => 1, 'name' => 'testid1' },
        { 'graphid' => 2, 'name' => 'testid2', filter: 'id' },
        { 'graphid' => 3, 'name' => 'testid3' }
      ]
    end
    let(:ids) { [3] }
    let(:method_name) { 'testmethod' }

    before do
      allow(graphs_mock).to receive(:log)
      allow(client).to receive(:api_request).with(
        method: 'graph.get',
        params: {
          filter: {
            host: 'testhost'
          },
          output: 'extend'
        }
      ).and_return(result)
    end

    context 'when filter is not nil or filter contains name' do
      it 'returns ids of filter matching graph' do
        expect(subject).to eq ids
      end
    end

    context 'when filter is nil' do
      let(:data) { { host: 'testhost' } }
      let(:ids) { [1, 2, 3] }

      it 'returns all the ids' do
        expect(subject).to eq ids
      end
    end

    context 'when filter is not nil or filter does not contain name' do
      let(:data) { { host: 'testhost', filter: 'wrong' } }
      let(:ids) { [] }

      it 'returns an empty array' do
        expect(subject).to be_empty
      end
    end
  end

  describe '.get_items' do
    subject { graphs_mock.get_items(data) }

    let(:data) { { testid: 222 } }
    let(:result) { { test: 1 } }
    let(:identify) { 'testid' }
    let(:method_name) { 'testmethod' }

    before do
      allow(client).to receive(:api_request).with(
        method: 'graphitem.get',
        params: {
          graphids: [data],
          output: 'extend'
        }
      ).and_return(result)
    end

    it { is_expected.to eq result }
  end

  describe '.get_or_create' do
    subject { graphs_mock.get_or_create(data) }

    let(:data) { { name: 'batman', templateid: 1234 } }
    let(:result) { [{ 'testkey' => '111', 'testid' => 1 }] }
    let(:id) { nil }
    let(:id_through_create) { 222 }

    before do
      allow(graphs_mock).to receive(:log)
      allow(graphs_mock).to receive(:get_id).with(name: data[:name], templateid: data[:templateid]).and_return(id)
      allow(graphs_mock).to receive(:create).with(data).and_return(id_through_create)
    end

    it 'logs the debug message' do
      expect(graphs_mock).to receive(:log).with("[DEBUG] Call get_or_create with parameters: #{data.inspect}")
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
    subject { graphs_mock.create_or_update(data) }

    let(:data) { { name: 'batman', templateid: 1234 } }
    let(:result) { [{ 'testkey' => '111', 'testid' => 1 }] }
    let(:key) { 'testkey' }
    let(:identify) { 'testid' }
    let(:id) { nil }
    let(:id_through_create) { 222 }
    let(:update_data) { { name: 'batman', templateid: 1234, graphid: id } }

    before do
      allow(graphs_mock).to receive(:log)
      allow(graphs_mock).to receive(:identify).and_return(identify)
      allow(graphs_mock).to receive(:get_id)
        .with(name: data[:name], templateid: data[:templateid]).and_return(id)
      allow(graphs_mock).to receive(:create).with(data).and_return(id_through_create)
      allow(graphs_mock).to receive(:_update).with(update_data).and_return(id)
    end

    context 'when Graph ID already exist' do
      let(:id) { '111' }

      it 'updates an object returns the Graph ID' do
        expect(subject).to eq id
      end
    end

    context 'when Graph ID does not exist' do
      it 'creates an object returns the newly created object ID' do
        expect(subject).to eq id_through_create
      end
    end
  end

  describe '._update' do
    subject { graphs_mock._update(data) }

    let(:data) { { name: 'batman', templateid: 1234 } }
    let(:id) { '111' }

    before do
      allow(graphs_mock).to receive(:update).with({ templateid: 1234 }).and_return(id)
    end

    it 'updates an object returns the Graph ID' do
      expect(subject).to eq id
    end
  end
end
