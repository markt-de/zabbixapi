require 'spec_helper'

describe 'ZabbixApi::Usermacros' do
  let(:usermacros_mock) { ZabbixApi::Usermacros.new(client) }
  let(:client) { double }

  describe '.identify' do
    subject { usermacros_mock.identify }

    it { is_expected.to eq 'macro' }
  end

  describe '.method_name' do
    subject { usermacros_mock.method_name }

    it { is_expected.to eq 'usermacro' }
  end

  describe '.get_id' do
    subject { usermacros_mock.get_id(data) }

    let(:data) { { 'testidentify' => 1 } }
    let(:symbolized_data) { { testidentify: 1 } }
    let(:result) { [{ 'hostmacroid' => '111', 'testidentify' => 1 }] }
    let(:key) { 'testkey' }
    let(:identify) { 'testidentify' }
    let(:id) { 111 }

    before do
      allow(usermacros_mock).to receive(:log)
      allow(usermacros_mock).to receive(:key).and_return(key)
      allow(usermacros_mock).to receive(:identify).and_return(identify)
      allow(usermacros_mock).to receive(:symbolize_keys).with(data).and_return(symbolized_data)
      allow(usermacros_mock).to receive(:request).with(
        symbolized_data,
        'usermacro.get',
        'hostmacroid'
      ).and_return(result)
    end

    it 'logs the debug message' do
      expect(usermacros_mock).to receive(:log).with("[DEBUG] Call get_id with parameters: #{data.inspect}")
      subject
    end

    context 'when data has `identify` as a key' do
      it 'symbolizes the data' do
        expect(usermacros_mock).to receive(:symbolize_keys).with(data)
        subject
      end

      it 'returns the id from the response' do
        expect(subject).to eq id
      end

      context 'when request response is empty' do
        let(:result) { [] }

        it { is_expected.to be_nil }
      end
    end

    context 'when data does not have `identify` as a key' do
      let(:identify) { 'wrongtestidentify' }

      it 'symbolizes the data' do
        expect(usermacros_mock).not_to receive(:symbolize_keys).with(data)
        expect { subject }.to raise_error(ZabbixApi::ApiError, "#{identify} not supplied in call to get_id")
      end
    end
  end

  describe '.get_id_global' do
    subject { usermacros_mock.get_id_global(data) }

    let(:data) { { 'testidentify' => 1 } }
    let(:symbolized_data) { { testidentify: 1 } }
    let(:result) { [{ 'globalmacroid' => '111', 'testidentify' => 1 }] }
    let(:key) { 'testkey' }
    let(:identify) { 'testidentify' }
    let(:id) { 111 }

    before do
      allow(usermacros_mock).to receive(:log)
      allow(usermacros_mock).to receive(:key).and_return(key)
      allow(usermacros_mock).to receive(:identify).and_return(identify)
      allow(usermacros_mock).to receive(:symbolize_keys).with(data).and_return(symbolized_data)
      allow(usermacros_mock).to receive(:request).with(
        symbolized_data,
        'usermacro.get',
        'globalmacroid'
      ).and_return(result)
    end

    it 'logs the debug message' do
      expect(usermacros_mock).to receive(:log).with("[DEBUG] Call get_id_global with parameters: #{data.inspect}")
      subject
    end

    context 'when data has `identify` as a key' do
      it 'symbolizes the data' do
        expect(usermacros_mock).to receive(:symbolize_keys).with(data)
        subject
      end

      it 'returns the id from the response' do
        expect(subject).to eq id
      end

      context 'when request response is empty' do
        let(:result) { [] }

        it { is_expected.to be_nil }
      end
    end

    context 'when data does not have `identify` as a key' do
      let(:identify) { 'wrongtestidentify' }

      it 'symbolizes the data' do
        expect(usermacros_mock).not_to receive(:symbolize_keys).with(data)
        expect { subject }.to raise_error(ZabbixApi::ApiError, "#{identify} not supplied in call to get_id_global")
      end
    end
  end

  describe '.get_full_data' do
    subject { usermacros_mock.get_full_data(data) }

    let(:data) { { 'hostid' => 1 } }
    let(:result) { [{ 'globalmacroid' => '111', 'testidentify' => 1 }] }

    before do
      allow(usermacros_mock).to receive(:log)
      allow(usermacros_mock).to receive(:request).with(
        data,
        'usermacro.get',
        'hostmacroid'
      ).and_return(result)
    end

    it 'logs the debug message' do
      expect(usermacros_mock).to receive(:log).with("[DEBUG] Call get_full_data with parameters: #{data.inspect}")
      subject
    end

    it { is_expected.to eq result }
  end

  describe '.get_full_data_global' do
    subject { usermacros_mock.get_full_data_global(data) }

    let(:data) { { 'hostid' => 1 } }
    let(:result) { [{ 'globalmacroid' => '111', 'testidentify' => 1 }] }

    before do
      allow(usermacros_mock).to receive(:log)
      allow(usermacros_mock).to receive(:request).with(
        data,
        'usermacro.get',
        'globalmacroid'
      ).and_return(result)
    end

    it 'logs the debug message' do
      expect(usermacros_mock).to receive(:log).with("[DEBUG] Call get_full_data_global with parameters: #{data.inspect}")
      subject
    end

    it { is_expected.to eq result }
  end

  describe '.create' do
    subject { usermacros_mock.create(data) }

    let(:data) { { 'hostid' => 1 } }
    let(:result) { [{ 'globalmacroid' => '111', 'testidentify' => 1 }] }

    before do
      allow(usermacros_mock).to receive(:request).with(
        data,
        'usermacro.create',
        'hostmacroids'
      ).and_return(result)
    end

    it { is_expected.to eq result }
  end

  describe '.create_global' do
    subject { usermacros_mock.create_global(data) }

    let(:data) { { 'hostid' => 1 } }
    let(:result) { [{ 'globalmacroid' => '111', 'testidentify' => 1 }] }

    before do
      allow(usermacros_mock).to receive(:request).with(
        data,
        'usermacro.createglobal',
        'globalmacroids'
      ).and_return(result)
    end

    it { is_expected.to eq result }
  end

  describe '.delete' do
    subject { usermacros_mock.delete(data) }

    let(:data) { { 'hostid' => 1 } }
    let(:result) { [{ 'globalmacroid' => '111', 'testidentify' => 1 }] }

    before do
      allow(usermacros_mock).to receive(:request).with(
        [data],
        'usermacro.delete',
        'hostmacroids'
      ).and_return(result)
    end

    it { is_expected.to eq result }
  end

  describe '.delete_global' do
    subject { usermacros_mock.delete_global(data) }

    let(:data) { { 'hostid' => 1 } }
    let(:result) { [{ 'globalmacroid' => '111', 'testidentify' => 1 }] }

    before do
      allow(usermacros_mock).to receive(:request).with(
        [data],
        'usermacro.deleteglobal',
        'globalmacroids'
      ).and_return(result)
    end

    it { is_expected.to eq result }
  end

  describe '.update' do
    subject { usermacros_mock.update(data) }

    let(:data) { { 'hostid' => 1 } }
    let(:result) { [{ 'globalmacroid' => '111', 'testidentify' => 1 }] }

    before do
      allow(usermacros_mock).to receive(:request).with(
        data,
        'usermacro.update',
        'hostmacroids'
      ).and_return(result)
    end

    it { is_expected.to eq result }
  end

  describe '.update_global' do
    subject { usermacros_mock.update_global(data) }

    let(:data) { { 'hostid' => 1 } }
    let(:result) { [{ 'globalmacroid' => '111', 'testidentify' => 1 }] }

    before do
      allow(usermacros_mock).to receive(:request).with(
        data,
        'usermacro.updateglobal',
        'globalmacroids'
      ).and_return(result)
    end

    it { is_expected.to eq result }
  end

  describe '.get_or_create_global' do
    subject { usermacros_mock.get_or_create_global(data) }

    let(:data) { { macro: 'testdesc', hostid: 'hostid' } }
    let(:result) { [{ 'testkey' => '111', 'testidentify' => 1 }] }
    let(:key) { 'testkey' }
    let(:identify) { 'testidentify' }
    let(:id) { nil }
    let(:id_through_create) { 222 }

    before do
      allow(usermacros_mock).to receive(:log)
      allow(usermacros_mock).to receive(:get_id_global).with(
        macro: data[:macro],
        hostid: data[:hostid]
      ).and_return(id)
      allow(usermacros_mock).to receive(:create_global).with(data).and_return(id_through_create)
    end

    it 'logs the debug message' do
      expect(usermacros_mock).to receive(:log).with("[DEBUG] Call get_or_create_global with parameters: #{data.inspect}")
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
    subject { usermacros_mock.create_or_update(data) }

    let(:data) { { macro: 'testdesc', hostid: 'hostid' } }
    let(:update_data) { { macro: 'testdesc', hostid: 'hostid', hostmacroid: hostmacroid } }
    let(:hostmacroid) { nil }
    let(:id_through_create) { 222 }
    let(:id_through_update) { 333 }

    before do
      allow(usermacros_mock).to receive(:log)
      allow(usermacros_mock).to receive(:get_id).with(
        macro: data[:macro],
        hostid: data[:hostid]
      ).and_return(hostmacroid)
      allow(usermacros_mock).to receive(:update).with(update_data).and_return(id_through_update)
      allow(usermacros_mock).to receive(:create).with(data).and_return(id_through_create)
    end

    context 'when ID already exist' do
      let(:hostmacroid) { 111 }

      it 'returns the existing ID' do
        expect(subject).to eq id_through_update
      end
    end

    context 'when id does not exist' do
      it 'returns the newly created ID' do
        expect(subject).to eq id_through_create
      end
    end
  end

  describe '.create_or_update_global' do
    subject { usermacros_mock.create_or_update_global(data) }

    let(:data) { { macro: 'testdesc', hostid: 'hostid' } }
    let(:update_data) { { macro: 'testdesc', hostid: 'hostid', globalmacroid: globalmacroid } }
    let(:globalmacroid) { nil }
    let(:id_through_create) { 222 }
    let(:id_through_update) { 333 }

    before do
      allow(usermacros_mock).to receive(:log)
      allow(usermacros_mock).to receive(:get_id_global).with(
        macro: data[:macro],
        hostid: data[:hostid]
      ).and_return(globalmacroid)
      allow(usermacros_mock).to receive(:update_global).with(update_data).and_return(id_through_update)
      allow(usermacros_mock).to receive(:create_global).with(data).and_return(id_through_create)
    end

    context 'when ID already exist' do
      let(:globalmacroid) { 111 }

      it 'returns the existing ID' do
        expect(subject).to eq id_through_update
      end
    end
  end

  # Testing this private method through create_global
  describe '.request' do
    subject { usermacros_mock.create_global(data) }

    let(:data) { { macro: 'testdesc', hostid: 'hostid' } }
    let(:result) { { 'globalmacroids' => ['111'] } }
    let(:method) { 'usermacro.createglobal' }

    before do
      allow(usermacros_mock).to receive(:log)
      allow(client).to receive(:api_request).with(
        method: method,
        params: data
      ).and_return(result)
    end

    context 'when api response is not empty and contains result key' do
      it 'returns the first hostmacroid ID' do
        expect(subject).to eq 111
      end
    end

    context 'when api response is empty' do
      let(:result) { {} }

      it { is_expected.to be_nil }
    end

    context 'when method contains `.get`' do
      subject { usermacros_mock.get_full_data_global(data) }

      let(:method) { 'usermacro.get' }

      before do
        allow(usermacros_mock).to receive(:log)
        allow(client).to receive(:api_request).with(
          method: method,
          params: data
        ).and_return(result)
      end

      context 'when result_key contains `global`' do
        before do
          allow('globalmacroid').to receive(:include?).with('global').and_return(false)
          allow(client).to receive(:api_request).with(
            method: method,
            params: {
              globalmacro: true,
              filter: data
            }
          ).and_return(result)
        end

        it { is_expected.to eq result }
      end
    end
  end

  # These two come from Basic and depend on key/keys. The usermacro API has no
  # "usermacroid", so they only work because key is overridden to hostmacroid.
  describe '.key' do
    subject { usermacros_mock.key }

    it { is_expected.to eq 'hostmacroid' }
  end

  describe '.keys' do
    subject { usermacros_mock.keys }

    it { is_expected.to eq 'hostmacroids' }
  end

  describe '.dump_by_id' do
    subject { usermacros_mock.dump_by_id(hostmacroid: 222) }

    let(:result) { [{ 'hostmacroid' => '222', 'macro' => '{$FOO}' }] }

    before do
      allow(usermacros_mock).to receive(:log)
      allow(client).to receive(:api_request).with(
        method: 'usermacro.get',
        params: {
          filter: { hostmacroid: 222 },
          output: 'extend'
        }
      ).and_return(result)
    end

    it 'filters on hostmacroid' do
      expect(subject).to eq result
    end
  end

  describe '.all' do
    subject { usermacros_mock.all }

    let(:result) { [{ 'hostmacroid' => '222', 'macro' => '{$FOO}' }] }

    before do
      allow(client).to receive(:api_request).with(
        method: 'usermacro.get',
        params: { output: 'extend' }
      ).and_return(result)
    end

    it 'maps macro to hostmacroid' do
      expect(subject).to eq('{$FOO}' => '222')
    end
  end
end
