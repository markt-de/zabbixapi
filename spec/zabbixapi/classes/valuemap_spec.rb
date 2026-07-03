require 'spec_helper'

describe 'ZabbixApi::ValueMaps' do
  let(:valuemaps_mock) { ZabbixApi::ValueMaps.new(client) }
  let(:client) { double }

  describe '.method_name' do
    subject { valuemaps_mock.method_name }

    it { is_expected.to eq 'valuemap' }
  end

  describe '.identify' do
    subject { valuemaps_mock.identify }

    it { is_expected.to eq 'name' }
  end

  describe '.key' do
    subject { valuemaps_mock.key }

    it { is_expected.to eq 'valuemapid' }
  end

  describe '.get_or_create' do
    subject { valuemaps_mock.get_or_create(data) }

    let(:data) { { name: 'fake_valuemap' } }

    before do
      allow(valuemaps_mock).to receive(:log)
      allow(valuemaps_mock).to receive(:get_id).with(name: data[:name]).and_return(id)
    end

    context 'when id is found' do
      let(:id) { 100 }

      it 'returns the id' do
        expect(subject).to eq 100
      end
    end

    context 'when id is not found' do
      let(:id) { nil }

      it 'creates a new valuemap' do
        expect(valuemaps_mock).to receive(:create).with(data)
        subject
      end
    end
  end

  describe '.create_or_update' do
    let(:data) { { name: 'fake_valuemap_name' } }
    let(:id) { 123 }

    before { allow(valuemaps_mock).to receive(:get_id).with(name: data[:name]).and_return(id) }

    context 'when id is found' do
      it 'updates with the valuemapid merged in' do
        expect(valuemaps_mock).to receive(:update).with(data.merge(valuemapid: id))
        valuemaps_mock.create_or_update(data)
      end
    end

    context 'when id is not found' do
      let(:id) { nil }

      it 'creates a new valuemap' do
        expect(valuemaps_mock).to receive(:create).with(data)
        valuemaps_mock.create_or_update(data)
      end
    end
  end
end
