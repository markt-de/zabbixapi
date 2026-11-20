# Contract: the recorded fixtures against the version of the server this run talks to
#   classes:  every fixture carries the version this run is talking to
#   not here: whether the recorded behaviour still holds - an answer can change while the version
#             string stays the same, and only re-recording a class proves that; the contents of any
#             fixture, which are the unit specs' own subject
#
# Why this file exists: the unit suite replays these recordings, so it stays green against a server
# that has since moved on, and nothing else in the suite would notice. This notices version drift
# only and fails loudly enough to prompt re-recording every fixture it names through its class's
# recorder under spec/recorders/.
#
# Safety: this spec creates nothing and writes nothing, reading only apiinfo.version and the fixture
# files on disk.
require 'spec_helper'
require 'json'

RSpec.describe 'the recorded fixtures', type: :acceptance do
  after(:all) { Live.teardown }

  it 'all carry the version this run is talking to' do
    live = Live.retrying('apiinfo.version') { Live.session.server.version }
    root = "#{Fixtures::ROOT}/"

    stale = Dir.glob(File.join(Fixtures::ROOT, '**', '*.json')).sort.filter_map do |path|
      recorded = JSON.parse(File.read(path))['server']
      next if recorded == live

      "#{path.delete_prefix(root)} recorded against #{recorded}"
    end

    expect(stale).to eq([])
  end
end
