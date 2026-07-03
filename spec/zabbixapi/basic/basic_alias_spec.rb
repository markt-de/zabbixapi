require 'spec_helper'

describe 'ZabbixApi::Basic' do
  let(:basic_mock) { ZabbixApi::Basic.new(client) }
  let(:client) { double('mock_client', options: {}, api_request: {}) }
  let(:data) { {} }

  after { subject }

  describe '.get' do
    subject { basic_mock.get(data) }

    before do
      allow(basic_mock).to receive(:get_full_data).with(data)
      allow(basic_mock).to receive(:method_name)
    end

    it 'calls get_full_data' do
      expect(basic_mock).to receive(:get_full_data).with(data)
    end
  end

  describe '.add' do
    subject { basic_mock.add(data) }

    before { allow(basic_mock).to receive(:create).with(data) }

    it 'calls create' do
      expect(basic_mock).to receive(:create).with(data)
    end
  end

  describe '.destroy' do
    subject { basic_mock.destroy(data) }

    before { allow(basic_mock).to receive(:delete).with(data) }

    it 'calls delete' do
      expect(basic_mock).to receive(:delete).with(data)
    end
  end
end
