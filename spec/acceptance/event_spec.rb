require 'spec_helper'

describe 'event' do
  before do
    @eventname = gen_name 'event'
    @usergroupid = zbx.usergroups.create(name: gen_name('usergroup'))
    @eventdata = {
      name: @eventname,
      eventsource: '0', # event source is a triggerid
      status: '0', # event is enabled
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

  context 'when incorrect method' do
    describe 'create' do
      it 'should raise ApiError' do
        expect{zbx.events.create(@eventdata)}.
          to raise_error(ZabbixApi::ApiError, /.*\"data\": \"Incorrect method \\\"event.create\\\"\.\"/)
      end
    end
  end
end
