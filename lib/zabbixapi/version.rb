class ZabbixApi
  # Gem version, tracking the targeted Zabbix version 7.0. At connect time {ZabbixApi::Client}
  # raises unless the server's `apiinfo.version` is a 7.x release or `ignore_version` is set.
  VERSION = '7.0.0-beta1'.freeze
end
