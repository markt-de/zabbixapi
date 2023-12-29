# encoding: utf-8

require 'spec_helper'

describe 'drule' do
  before do
    @drulename = gen_name 'drule'
    @usergroupid = zbx.usergroups.create(:name => gen_name('usergroup'))
    @dcheckdata = [{
      :type => '9', # zabbix agent
      :uniq => '0', # (default) do not use this check as a uniqueness criteria
      :key_ => 'system.hostname',
      :ports => '10050',
    }]
    @druledata = {
      :name => @drulename,
      :delay => '60',
      :status => '0', # action is enabled
      :iprange => '192.168.0.0/24', # iprange to discover zabbix agents in
      :dchecks => @dcheckdata,
    }
  end

  context 'when not exists' do
    describe 'create' do
      it 'should return integer id' do
        druleid = zbx.drules.create(@druledata)
        expect(druleid).to be_kind_of(Integer)
      end
    end
  end

  context 'when exists' do
    before do
      @druleid = zbx.drules.create(@druledata)
    end

    describe 'create_or_update' do
      it 'should return id' do
        expect(zbx.drules.create_or_update(@druledata)).to eq @druleid
      end
    end

    describe 'delete' do
      it 'should return id' do
        expect(zbx.drules.delete(@druleid)).to eq @druleid
      end
    end
  end
end
