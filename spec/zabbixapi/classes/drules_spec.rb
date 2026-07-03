require 'spec_helper'

describe 'ZabbixApi::Drules' do
  let(:drules_mock) { ZabbixApi::Drules.new(client) }
  let(:client) { double }

  describe '.method_name' do
    subject { drules_mock.method_name }

    it { is_expected.to eq 'drule' }
  end

  describe '.identify' do
    subject { drules_mock.identify }

    it { is_expected.to eq 'name' }
  end

  describe '.default_options' do
    subject { drules_mock.default_options }

    let(:result) do
      {
        name: nil,
        iprange: nil,
        delay: 3600,
        status: 0,
        concurrency_max: 0
      }
    end

    it { is_expected.to eq result }
  end

  describe '.get_or_create' do
    subject { drules_mock.get_or_create(data) }

    let(:data) { { name: 'discovery-rule' } }
    let(:id_through_create) { 222 }

    before do
      allow(drules_mock).to receive(:log)
      allow(drules_mock).to receive(:get_id).with(name: data[:name]).and_return(id)
      allow(drules_mock).to receive(:create).with(data).and_return(id_through_create)
    end

    context 'when id already exists' do
      let(:id) { 111 }

      it 'returns the existing id' do
        expect(subject).to eq id
      end
    end

    context 'when id does not exist' do
      let(:id) { nil }

      it 'returns the newly created id' do
        expect(subject).to eq id_through_create
      end
    end
  end

  describe '.create_or_update' do
    let(:data) { { name: 'discovery-rule' } }

    before do
      allow(drules_mock).to receive(:get_id).with(name: data[:name]).and_return(id)
      allow(drules_mock).to receive(:update)
      allow(drules_mock).to receive(:create)
    end

    context 'when id is found' do
      let(:id) { 123 }

      it 'updates with the druleid merged in' do
        expect(drules_mock).to receive(:update).with(data.merge(druleid: id))
        drules_mock.create_or_update(data)
      end
    end

    context 'when id is not found' do
      let(:id) { nil }

      it 'creates a new drule' do
        expect(drules_mock).to receive(:create).with(data)
        drules_mock.create_or_update(data)
      end
    end
  end
end
