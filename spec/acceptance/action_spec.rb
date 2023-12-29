require 'spec_helper'

describe 'action' do
  before do
    @actionname = gen_name 'action'
    @usergroupid = zbx.usergroups.create(name: gen_name('usergroup'))
    @actiondata = {
      name: @actionname,
      eventsource: '0', # event source is a triggerid
      status: '0', # action is enabled
      esc_period: '120', # how long each step should take
      def_shortdata: 'Email header',
      def_longdata: 'Email content',
      maintenance_mode: '1',
      filter: {
        evaltype: '1', # perform 'and' between the conditions
        conditions: [
          {
            conditiontype: '3', # trigger name
            operator: '2', # like
            value: 'pattern' # the pattern
          },
          {
            conditiontype: '4', # trigger severity
            operator: '5', # >=
            value: '3' # average
          }
        ]
      },
      operations: [
        {
          operationtype: '0', # send message
          opmessage_grp: [ # who the message will be sent to
            {
              usrgrpid: @usergroupid
            }
          ],
          opmessage: {
            default_msg: '0', # use default message
            mediatypeid: '1' # email id
          }
        }
      ],
      recovery_operations: [
        {
          operationtype: '11', # send recovery message
          opmessage_grp: [ # who the message will be sent to
            {
              usrgrpid: @usergroupid
            }
          ],
          opmessage: {
            default_msg: '0', # use default message
            mediatypeid: '1' # email id
          }
        }
      ]
    }
  end

  context 'when not exists' do
    describe 'create' do
      it 'should return integer id' do
        actionid = zbx.actions.create(@actiondata)
        expect(actionid).to be_kind_of(Integer)
      end
    end
  end

  context 'when exists' do
    before do
      @actionid = zbx.actions.create(@actiondata)
    end

    describe 'create_or_update' do
      it 'should return id' do
        expect(zbx.actions.create_or_update(@actiondata)).to eq @actionid
      end
    end

    describe 'delete' do
      it 'should return id' do
        expect(zbx.actions.delete(@actionid)).to eq @actionid
      end
    end
  end
end
