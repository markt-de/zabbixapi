require 'spec_helper'

describe 'valuemap' do
  before :all do
    @valuemap = gen_name 'valuemap'
  end

  context 'when not exists' do
    describe 'create' do
      it 'should return an integer id' do
        valuemapid = zbx.valuemaps.create_or_update(
          name: @valuemap,
          mappings: [
            'newvalue' => 'test',
            'value' => 'test'
          ]
        )
        expect(valuemapid).to be_kind_of(Integer)
      end
    end
  end

  context 'when exists' do
    before do
      @valuemapid = zbx.valuemaps.create_or_update(
        name: @valuemap,
        mappings: [
          'newvalue' => 'test',
          'value' => 'test'
        ]
      )
    end

    describe 'create_or_update' do
      it 'should return id' do
        expect(
          zbx.valuemaps.create_or_update(
            name: @valuemap,
            mappings: [
              'newvalue' => 'test',
              'value' => 'test'
            ]
          )
        ).to eq @valuemapid
      end

      it 'should return id' do
        expect(@valuemapid).to eq @valuemapid
      end
    end
  end
end
