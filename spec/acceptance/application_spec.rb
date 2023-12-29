require 'spec_helper'

describe 'application' do
  before :all do
    @hostgroup = gen_name 'hostgroup'
    @hostgroupid = zbx.hostgroups.create(name: @hostgroup)
    @template = gen_name 'template'
    @templateid = zbx.templates.create(
      host: @template,
      groups: [groupid: @hostgroupid]
    )
  end

  context 'when name not exists' do
    before do
      @application = gen_name 'application'
    end

    describe 'create' do
      it 'should return integer id' do
        applicationid = zbx.applications.create(
          name: @application,
          hostid: @templateid
        )
        expect(applicationid).to be_kind_of(Integer)
      end
    end

    describe 'get_id' do
      it 'should return nil' do
        expect(zbx.applications.get_id(name: @application)).to be_kind_of(NilClass)
      end
    end
  end

  context 'when name exists' do
    before :all do
      @application = gen_name 'application'
      @applicationid = zbx.applications.create(
        name: @application,
        hostid: @templateid
      )
    end

    describe 'get_or_create' do
      it 'should return id of application' do
        expect(
          zbx.applications.get_or_create(
            name: @application,
            hostid: @templateid
          )
        ).to eq @applicationid
      end
    end

    describe 'get_full_data' do
      it 'should contains created application' do
        expect(zbx.applications.get_full_data(name: @application)[0]).to include('name' => @application)
      end
    end

    describe 'get_id' do
      it 'should return id of application' do
        expect(zbx.applications.get_id(name: @application)).to eq @applicationid
      end
    end

    describe 'create_or_update' do
      it 'should return id of updated application' do
        expect(
          zbx.applications.create_or_update(
            name: @application,
            hostid: @templateid
          )
        ).to eq @applicationid
      end
    end

    describe 'delete' do
      it 'should return id' do
        expect(zbx.applications.delete(@applicationid)).to eq @applicationid
      end
    end
  end
end
