require 'spec_helper'

describe 'configuration' do
  before :all do
    @hostgroup = gen_name 'hostgroup'
    @hostgroup_id = zbx.hostgroups.create(name: @hostgroup)
    @template    = gen_name 'template'
    @template_id = zbx.templates.create(
      host: @template,
      groups: [groupid: @hostgroup_id]
    )
    @source = zbx.configurations.export(
      format: 'xml',
      options: {
        templates: [@template_id]
      }
    )
    @item = gen_name 'item'
    @item_id = zbx.items.create(
      name: @item,
      description: 'item',
      key_: 'proc.num[aaa]',
      type: 0,
      value_type: 3,
      hostid: zbx.templates.get_id(host: @template)
    )
  end

  after :all do
    zbx.items.delete(zbx.items.get_id(name: @item))
    zbx.templates.delete(zbx.templates.get_id(host: @template))
    zbx.hostgroups.delete(zbx.hostgroups.get_id(name: @hostgroup))
  end

  context 'when object not exists' do
    describe 'import with createMissing' do
      before do
        zbx.items.delete(@item_id)
        zbx.templates.delete(@template_id)
        zbx.hostgroups.delete(@hostgroup_id)
        zbx.configurations.import(
          format: 'xml',
          rules: {
            groups: {
              createMissing: true
            },
            templates: {
              createMissing: true
            }
          },
          source: @source
        )
      end

      it 'should create object' do
        expect(zbx.hostgroups.get_id(name: @hostgroup)).to be_kind_of(Integer)
        expect(zbx.templates.get_id(host: @template)).to be_kind_of(Integer)
      end
    end
  end

  context 'when object exists' do
    describe 'export' do
      before do
        zbx.items.create(
          name: @item,
          description: 'item',
          key_: 'proc.num[aaa]',
          type: 0,
          value_type: 3,
          hostid: zbx.templates.get_id(host: @template)
        )
      end

      it 'should export updated object' do
        expect(
          zbx.configurations.export(
            format: 'xml',
            options: {
              templates: [zbx.templates.get_id(host: @template)]
            }
          )
        ).to match(/#{@item}/)
      end
    end

    describe 'import with updateExisting' do
      before do
        @source_updated = zbx.configurations.export(
          format: 'xml',
          options: {
            templates: [zbx.templates.get_id(host: @template)]
          }
        )
        zbx.items.delete(zbx.items.get_id(name: @item))
        zbx.configurations.import(
          format: 'xml',
          rules: {
            templates: {
              updateExisting: true
            },
            items: {
              createMissing: true
            }
          },
          source: @source_updated
        )
      end

      it 'should update object' do
        expect(
          zbx.configurations.export(
            format: 'xml',
            options: {
              templates: [zbx.templates.get_id(host: @template)]
            }
          )
        ).to match(/#{@item}/)
      end
    end
  end
end
