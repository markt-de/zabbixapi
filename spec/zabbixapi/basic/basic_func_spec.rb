require 'spec_helper'

describe 'ZabbixApi::Basic' do
  let(:basic_mock) { ZabbixApi::Basic.new(client) }
  let(:client) { double }

  describe '.log' do
    subject { basic_mock.log(message) }

    let(:message) { 'test-message' }
    let(:debug) { true }
    let(:client) { instance_double('ZabbixApi::Client', options: { debug: debug }) }

    context 'when debug is set to true' do
      it 'prints the message' do
        expect(basic_mock).to receive(:puts).with(message)
        subject
      end
    end

    context 'when debug is set to false' do
      let(:debug) { false }

      it 'does not print the message' do
        expect(basic_mock).not_to receive(:puts).with(message)
        subject
      end
    end
  end

  describe '.symbolize_keys' do
    subject { basic_mock.symbolize_keys(object) }

    let(:object) { { 'test' => { 'one' => 1, 'two' => [1, 2] } } }
    let(:symbolized_object) { { test: { one: 1, two: [1, 2] } } }

    context 'when hash with string keys is passed' do
      it 'converts all the string keys to symbol' do
        expect(subject).to eq symbolized_object
      end
    end

    context 'when string object is passed' do
      let(:object) { 'test-this' }
      let(:symbolized_object) { 'test-this' }

      it 'returns the same object back' do
        expect(subject).to eq symbolized_object
      end
    end

    context 'when nil object is passed' do
      let(:object) { nil }
      let(:symbolized_object) { nil }

      it 'returns nil back' do
        expect(subject).to eq symbolized_object
      end
    end
  end

  describe '.normalize_hash' do
    subject { basic_mock.normalize_hash(hash) }

    let(:hash) { { 'one' => 1, 'two' => [1, 2] } }
    let(:hash_dup) { { 'one' => 1, 'two' => [1, 2] } }
    let(:symbolized_object) { { 'one' => '1', 'two' => normalized_array } }
    let(:normalized_array) { %w[1 2] }

    before do
      allow(basic_mock).to receive(:normalized_array).with([1, 2]).and_return(normalized_array)
      allow(hash).to receive(:dup).and_return(hash_dup)
    end

    context 'when hash is passed' do
      it 'normalizes the hash' do
        expect(subject).to eq symbolized_object
      end

      it 'duplicates the hash before modifying' do
        expect(hash).to receive(:dup)
        subject
      end
    end

    context 'when passed hash contains key hostid' do
      let(:hash) { { one: 1, two: [1, 2], hostid: 3 } }
      let(:hash_dup) { { one: 1, two: [1, 2], hostid: 3 } }
      let(:symbolized_object) { { one: '1', two: %w[1 2] } }

      it 'deletes hostid from hash during normalization' do
        expect(subject).to eq symbolized_object
      end
    end
  end

  describe '.normalize_array' do
    subject { basic_mock.normalize_array(array) }

    let(:array) { ['one', [2, 3], { four: 5 }] }
    let(:normalized_array) { ['one', %w[2 3], normalized_hash] }
    let(:normalized_hash) { { four: '5' } }

    before do
      allow(basic_mock).to receive(:normalize_hash).with({ four: 5 }).and_return(normalized_hash)
    end

    context 'when array is passed' do
      it 'normalizes the array' do
        expect(subject).to eq normalized_array
      end
    end
  end

  describe '.parse_keys' do
    subject { basic_mock.parse_keys(data) }

    let(:data) { { test: ['1'] } }
    let(:expected) { 1 }

    before do
      allow(basic_mock).to receive(:keys).and_return(:test)
    end

    context 'when hash is passed' do
      it 'returns the object id' do
        expect(subject).to eq expected
      end
    end

    context 'when passed hash is empty' do
      let(:data) { {} }

      it { is_expected.to be_nil }
    end

    context 'when TrueClass is passed' do
      let(:data) { true }

      it { is_expected.to be_truthy }
    end

    context 'when FalseClass is passed' do
      let(:data) { false }

      it { is_expected.to be_falsy }
    end
  end

  describe '.merge_params' do
    subject { basic_mock.merge_params(first_hash, second_hash) }

    let(:first_hash) { { test1: 1 } }
    let(:first_hash_dup) { { test1: 1 } }
    let(:second_hash) { { test2: 2 } }
    let(:expected) { { test1: 1, test2: 2 } }

    before { allow(first_hash).to receive(:dup).and_return(first_hash_dup) }

    it { is_expected.to eq expected }

    it 'merged two hashes in new hash object' do
      expect(first_hash).to receive(:dup)
      subject
    end
  end
end
