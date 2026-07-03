require 'spec_helper'

describe 'ZabbixApi::Hosts' do
  let(:hosts_mock) { ZabbixApi::Hosts.new(client) }
  let(:client) { double }

  describe '.method_name' do
    subject { hosts_mock.method_name }

    it { is_expected.to eq 'host' }
  end

  describe '.identify' do
    subject { hosts_mock.identify }

    it { is_expected.to eq 'host' }
  end

  describe '.dump_by_id' do
    subject { hosts_mock.dump_by_id(data) }

    let(:data) { { testkey: 222 } }
    let(:result) { { test: 1 } }
    let(:key) { 'testkey' }

    before do
      allow(hosts_mock).to receive(:log)
      allow(hosts_mock).to receive(:key).and_return(key)
      allow(client).to receive(:api_request).with(
        method: 'host.get',
        params: {
          filter: {
            testkey: 222
          },
          output: 'extend',
          selectHostGroups: 'extend'
        }
      ).and_return(result)
    end

    it 'logs debug message' do
      expect(hosts_mock).to receive(:log).with("[DEBUG] Call dump_by_id with parameters: #{data.inspect}")
      subject
    end

    it { is_expected.to eq result }
  end

  describe '.default_options' do
    subject { hosts_mock.default_options }

    let(:result) do
      {
        host: nil,
        interfaces: [],
        status: 0,
        groups: []
      }
    end

    it { is_expected.to eq result }
  end

  describe '.unlink_templates' do
    subject { hosts_mock.unlink_templates(data) }

    let(:data) { { hosts_id: 222, templates_id: 333 } }
    let(:result) { { test: 1 } }
    let(:key) { 'testkey' }

    before do
      allow(hosts_mock).to receive(:log)
      allow(hosts_mock).to receive(:key).and_return(key)
      allow(client).to receive(:api_request).with(
        method: 'host.massRemove',
        params: {
          hostids: data[:hosts_id],
          templateids: data[:templates_id]
        }
      ).and_return(result)
    end

    context 'when result is an empty hash' do
      let(:result) { {} }

      it { is_expected.to be_falsy }
    end

    context 'when result is not an empty hash' do
      it { is_expected.to be_truthy }
    end
  end

  describe '.create_or_update' do
    subject { hosts_mock.create_or_update(data) }

    let(:data) { { host: 'batman' } }
    let(:result) { [{ 'testkey' => '111', 'testidentify' => 1 }] }
    let(:key) { 'testkey' }
    let(:identify) { 'testidentify' }
    let(:id) { nil }
    let(:id_through_create) { 222 }
    let(:update_data) { { host: 'batman', hostid: 1234 } }

    before do
      allow(hosts_mock).to receive(:log)
      allow(hosts_mock).to receive(:identify).and_return(identify)
      allow(hosts_mock).to receive(:get_id)
        .with(host: data[:host]).and_return(id)
      allow(hosts_mock).to receive(:create).with(data).and_return(id_through_create)
      allow(hosts_mock).to receive(:update).with(update_data).and_return(id)
    end

    context 'when Host ID already exist' do
      let(:id) { 1234 }

      it 'updates an object returns the Host ID' do
        expect(subject).to eq id
      end
    end

    context 'when Host ID does not exist' do
      it 'creates an object returns the newly created object ID' do
        expect(subject).to eq id_through_create
      end
    end
  end
end
