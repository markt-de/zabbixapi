Examples Index
====================

- [Quick Start](README.md#quick-start)
    - [Connect](README.md#connect)
    - [Create Host](README.md#create-host)
    - [Custom Queries](README.md#custom-queries)
- Supported Zabbix Objects
    - [Actions](Actions.md)
    - [Configurations](Configurations.md)
    - [Graphs](Graphs.md)
    - [Hostgroups](Hostgroups.md)
    - [Hosts](Hosts.md)
    - [Httptests](Httptests.md)
    - [Items](Items.md)
    - [Maintenance](Maintenance.md)
    - [MediaTypes](MediaTypes.md)
    - [Problems](Problems.md)
    - [Proxies](Proxies.md)
    - [Templates](Templates.md)
    - [Triggers](Triggers.md)
    - [Usergroups](Usergroups.md)
    - [Usermacros](Usermacros.md)
    - [Users](Users.md)

# Quick Start

## Connect

### Standard
```ruby
require "zabbixapi"

zbx = ZabbixApi.connect(
  :url => 'http://localhost/zabbix/api_jsonrpc.php',
  :user => 'Admin',
  :password => 'zabbix'
)
```

### Ignore Zabbix API version
```ruby
require "zabbixapi"

zbx = ZabbixApi.connect(
  :url => 'http://localhost/zabbix/api_jsonrpc.php',
  :user => 'Admin',
  :password => 'zabbix',
  :ignore_version => true
)
```

### Basic Auth
```ruby
require "zabbixapi"

zbx = ZabbixApi.connect(
  :url => 'http://localhost/zabbix/api_jsonrpc.php',
  :user => 'Admin',
  :password => 'zabbix',
  :http_password => 'foo',
  :http_user => 'bar'
)
```

## Logout
```ruby
require "zabbixapi"

zbx = ZabbixApi.connect(
  :url => 'http://localhost/zabbix/api_jsonrpc.php',
  :user => 'Admin',
  :password => 'zabbix'
)

# Do stuff

zbx.logout
```

## Create Host
```ruby
zbx.hosts.create(
  :host => host.fqdn,
  :interfaces => [
    {
      :type => 1,
      :main => 1,
      :ip => '10.0.0.1',
      :dns => 'server.example.org',
      :port => 10050,
      :useip => 0
    }
  ],
  :groups => [ :groupid => zbx.hostgroups.get_id(:name => "hostgroup") ]
)
```

## Custom Queries
```ruby
zbx.query(
  :method => "apiinfo.version",
  :params => {}
)
```
