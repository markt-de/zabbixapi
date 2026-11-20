require 'zabbixapi'

# live.rb first: import_guard.rb sorts before it and reads constants live.rb defines at load time.
require_relative 'support/live/live'
Dir[File.join(__dir__, 'support', '**', '*.rb')].sort.each { |file| require file }

RSpec.configure do |config|
  config.disable_monkey_patching!
  config.expect_with(:rspec) { |expectations| expectations.syntax = :expect }
  config.mock_with(:rspec) { |mocks| mocks.verify_partial_doubles = true }

  # Everything under spec/acceptance/ reaches the server ZABBIX_URL names, and runs only when both
  # ZABBIX_URL and ZABBIX_TOKEN are set; the unit suite never opens a socket.
  config.define_derived_metadata(file_path: %r{/spec/acceptance/}) do |metadata|
    metadata[:type] = :acceptance
  end
  config.filter_run_excluding(type: :acceptance) unless Live.configured?
end
