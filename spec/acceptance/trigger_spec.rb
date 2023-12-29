require 'spec_helper'

describe 'trigger' do
  before :all do
    @hostgroup = gen_name 'hostgroup'
    @hostgroupid = zbx.hostgroups.create(name: @hostgroup)
    @template = gen_name 'template'
    @templateid = zbx.templates.create(
      host: @template,
      groups: [groupid: @hostgroupid]
    )
    @application = gen_name 'application'
    @applicationid = zbx.applications.create(
      name: @application,
      hostid: @templateid
    )
    @item = gen_name 'item'
    @proc = "proc.num[#{gen_name 'proc'}]"
    @itemid = zbx.items.create(
      name: @item,
      key_: @proc,
      status: 0,
      hostid: @templateid,
      applications: [@applicationid]
    )
  end

  context 'when name not exists' do
    describe 'create' do
      it 'should return integer id' do
        @trigger = gen_name 'trigger'
        triggerid = zbx.triggers.create(
          description: @trigger,
          expression: "{#{@template}:#{@proc}.last(0)}<1",
          comments: 'Bla-bla is faulty (disaster)',
          priority: 5,
          status: 0,
          type: 0,
          tags: [
            {
              tag: 'proc',
              value: @proc.to_s
            },
            {
              tag: 'error',
              value: ''
            }
          ]
        )
        expect(triggerid).to be_kind_of(Integer)
      end
    end
  end

  context 'when name exists' do
    before :all do
      @trigger = gen_name 'trigger'
      @triggerid = zbx.triggers.create(
        description: @trigger,
        expression: "{#{@template}:#{@proc}.last(0)}<1",
        comments: 'Bla-bla is faulty (disaster)',
        priority: 5,
        status: 0,
        type: 0,
        tags: [
          {
            tag: 'proc',
            value: @proc.to_s
          },
          {
            tag: 'error',
            value: ''
          }
        ]
      )
    end

    describe 'get_id' do
      it 'should return id' do
        expect(zbx.triggers.get_id(description: @trigger)).to eq @triggerid
      end
    end

    describe 'create_or_update' do
      it 'should return id of updated trigger' do
        expect(
          zbx.triggers.create_or_update(
            description: @trigger,
            hostid: @templateid
          )
        ).to eq @triggerid
      end
    end

    describe 'delete' do
      it 'should return id' do
        expect(zbx.triggers.delete(@triggerid)).to eq @triggerid
      end
    end
  end
end
