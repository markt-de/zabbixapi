require 'zabbixapi'

RSpec.configure do |config|
  config.define_derived_metadata(file_path: %r{/spec/acceptance/}) do |metadata|
    metadata[:type] = :acceptance
  end

  # Don't run acceptance tests unless a host is provided
  unless (ENV.key?('ZABBIX_HOST_URL') || ENV.key?('ZABBIX_RUN_ACCEPTANCE'))
    config.filter_run_excluding type: :acceptance
  end
end

def zbx
  # settings
  @api_url = ENV['ZABBIX_HOST_URL'] || 'http://localhost:8080/api_jsonrpc.php'
  @api_login = ENV['ZABBIX_USERNAME'] || 'Admin'
  @api_password = ENV['ZABBIX_PASSWORD'] || 'zabbix'

  @zbx ||= ZabbixApi.connect(
    url: @api_url,
    user: @api_login,
    password: @api_password,
    debug: ENV['ZABBIX_DEBUG'] ? true : false
  )
end

def gen_id
  rand(1_000_000_000)
end

def gen_name(prefix)
  suffix = rand(1_000_000_000)
  "#{prefix}_#{suffix}"
end
