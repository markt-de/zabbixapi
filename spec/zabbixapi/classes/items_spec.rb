require 'spec_helper'

describe 'ZabbixApi::Items' do
  let(:items_mock) { ZabbixApi::Items.new(client) }
  let(:client) { double }

  describe '.method_name' do
    subject { items_mock.method_name }

    it { is_expected.to eq 'item' }
  end

  describe '.identify' do
    subject { items_mock.identify }

    it { is_expected.to eq 'name' }
  end

  describe '.default_options' do
    subject { items_mock.default_options }

    let(:result) do
      {
        name: nil,
        key_: nil,
        hostid: nil,
        delay: '60',
        history: '3600',
        status: 0,
        type: 7,
        snmp_oid: '',
        value_type: 3,
        units: '',
        trends: '86400',
        logtimefmt: '',
        valuemapid: 0,
        authtype: 0,
        username: '',
        password: '',
        publickey: '',
        privatekey: '',
        params: '',
        ipmi_sensor: ''
      }
    end

    it { is_expected.to eq result }
  end

  describe '.get_or_create' do
    subject { items_mock.get_or_create(data) }

    let(:data) { { name: 'batman', hostid: 1234 } }
    let(:result) { [{ 'testkey' => '111', 'testidentify' => 1 }] }
    let(:id) { nil }
    let(:id_through_create) { 222 }

    before do
      allow(items_mock).to receive(:log)
      allow(items_mock).to receive(:get_id).with(name: data[:name], hostid: data[:hostid]).and_return(id)
      allow(items_mock).to receive(:create).with(data).and_return(id_through_create)
    end

    it 'logs the debug message' do
      expect(items_mock).to receive(:log).with("[DEBUG] Call get_or_create with parameters: #{data.inspect}")
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
    subject { items_mock.create_or_update(data) }

    let(:data) { { name: 'batman', hostid: '1234' } }
    let(:result) { [{ 'testkey' => '111', 'testidentify' => 1 }] }
    let(:key) { 'testkey' }
    let(:identify) { 'testidentify' }
    let(:itemid) { nil }
    let(:id_through_create) { 222 }
    let(:update_data) { { name: data[:name], hostid: data[:hostid], itemid: itemid } }

    before do
      allow(items_mock).to receive(:log)
      allow(items_mock).to receive(:identify).and_return(identify)
      allow(items_mock).to receive(:get_id)
        .with(name: data[:name], hostid: data[:hostid]).and_return(itemid)
      allow(items_mock).to receive(:create).with(data).and_return(id_through_create)
      allow(items_mock).to receive(:update).with(update_data).and_return(itemid)
    end

    context 'when Item ID already exist' do
      let(:itemid) { 1234 }

      it 'updates an object returns the Item ID' do
        expect(subject).to eq itemid
      end
    end

    context 'when Item ID does not exist' do
      it 'creates an object returns the newly created object ID' do
        expect(subject).to eq id_through_create
      end
    end
  end
end
