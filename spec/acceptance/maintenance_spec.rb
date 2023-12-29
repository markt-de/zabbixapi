require 'spec_helper'

describe 'maintenance' do
  context 'when not exists' do
    before :all do
      @hostgroupid = zbx.hostgroups.create(name: "hostgroup_#{rand(1_000_000)}")
    end

    describe 'create' do
      it 'should return integer id after creation' do
        maintenanceid = zbx.maintenance.create(
          name: "maintenance_#{rand(1_000_000)}",
          groupids: [@hostgroupid],
          active_since: '1358844540',
          active_till: '1390466940',
          timeperiods: [timeperiod_type: 3, every: 1, dayofweek: 64, start_time: 64_800, period: 3_600]
        )
        expect(maintenanceid).to be_kind_of(Integer)
        zbx.maintenance.delete(maintenanceid)
      end
    end

    after :all do
      zbx.hostgroups.delete(@hostgroupid)
    end
  end

  context 'when exists' do
    before :all do
      @hostgroupid_when_exists = zbx.hostgroups.create(name: "hostgroup_#{rand(1_000_000)}")
      @maintenance = gen_name('maintenance')
      @maintenanceid = zbx.maintenance.create(
        name: @maintenance,
        groupids: [@hostgroupid_when_exists],
        active_since: '1358844540',
        active_till: '1390466940',
        timeperiods: [timeperiod_type: 3, every: 1, dayofweek: 64, start_time: 64_800, period: 3_600]
      )
    end

    describe 'get_id' do
      it 'should return id' do
        expect(zbx.maintenance.get_id(name: @maintenance)).to eq @maintenanceid
      end

      it 'should return nil for not existing group' do
        expect(zbx.maintenance.get_id(name: "#{@maintenance}______")).to be_kind_of(NilClass)
      end
    end

    describe 'get_or_create' do
      it 'should return id of existing maintenance' do
        expect(zbx.maintenance.get_or_create(name: @maintenance)).to eq @maintenanceid
      end
    end

    describe 'create_or_update' do
      it 'should return id of maintenance' do
        expect(zbx.maintenance.create_or_update(name: @maintenance)).to eq @maintenanceid
      end
    end

    describe 'all' do
      it 'should contains created maintenance' do
        expect(zbx.maintenance.all).to include(@maintenance => @maintenanceid.to_s)
      end
    end

    describe 'delete' do
      it 'shold return id' do
        expect(zbx.maintenance.delete(@maintenanceid)).to eq @maintenanceid
      end
    end

    after :all do
      zbx.hostgroups.delete(@hostgroupid_when_exists)
    end
  end
end
