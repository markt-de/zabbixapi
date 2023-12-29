require 'spec_helper'

describe 'hostgroup' do
  context 'when not exists' do
    describe 'create' do
      it 'should return integer id after creation' do
        hostgroupid = zbx.hostgroups.create(name: "hostgroup_#{rand(1_000_000)}")
        expect(hostgroupid).to be_kind_of(Integer)
      end
    end
  end

  context 'when exists' do
    before :all do
      @hostgroup = gen_name('hostgroup')
      @hostgroupid = zbx.hostgroups.create(name: @hostgroup)
    end

    describe 'get_id' do
      it 'should return id' do
        expect(zbx.hostgroups.get_id(name: @hostgroup)).to eq @hostgroupid
      end

      it 'should return nil for not existing group' do
        expect(zbx.hostgroups.get_id(name: "#{@hostgroup}______")).to be_kind_of(NilClass)
      end
    end

    describe 'get_or_create' do
      it 'should return id of existing hostgroup' do
        expect(zbx.hostgroups.get_or_create(name: @hostgroup)).to eq @hostgroupid
      end
    end

    describe 'create_or_update' do
      it 'should return id of hostgroup' do
        expect(zbx.hostgroups.create_or_update(name: @hostgroup)).to eq @hostgroupid
      end
    end

    describe 'all' do
      it 'should contains created hostgroup' do
        expect(zbx.hostgroups.all).to include(@hostgroup => @hostgroupid.to_s)
      end
    end

    describe 'delete' do
      it 'shold return id' do
        expect(zbx.hostgroups.delete(@hostgroupid)).to eq @hostgroupid
      end
    end
  end
end
