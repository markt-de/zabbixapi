# Ruby Zabbix Api Module

[![Gem Version](http://img.shields.io/gem/v/zabbixapi.svg)][gem]
[![Build Status](https://github.com/anapsix/zabbixapi/workflows/CI/badge.svg)][github-ci]

[gem]: https://rubygems.org/gems/zabbixapi
[github-ci]: https://github.com/express42/zabbixapi/actions?query=workflow%3ACI

Simple and lightweight ruby module for working with [Zabbix][Zabbix] via the [Zabbix API][Zabbix API]

## Installation
```sh
# latest
gem install zabbixapi

# specific version
gem install zabbixapi -v 4.2.0
```

## Documentation
[http://rdoc.info/gems/zabbixapi][documentation]

[documentation]: http://rdoc.info/gems/zabbixapi

## Examples
[https://github.com/express42/zabbixapi/tree/master/examples][examples]

[examples]: https://github.com/express42/zabbixapi/tree/master/examples

## Version Policy

**NOTE:** `master` branch is used for ongoing development on Zabbix API 5.x (5.0 and 5.2).

We support only two last versions of zabbix (5.0 and 5.2), so you should consider all previous versions deprecated.

* Zabbix 1.8.2 (api version 1.2) | zabbixapi 0.6.x | [branch zabbix1.8](https://github.com/express42/zabbixapi/tree/zabbix1.8)
* Zabbix 1.8.9 (api version 1.3) | zabbixapi 0.6.x | [branch zabbix1.8](https://github.com/express42/zabbixapi/tree/zabbix1.8)
* Zabbix 2.0.x (api version 1.4 -> 2.0.10) | zabbixapi 2.0.x | [branch zabbix2.0](https://github.com/express42/zabbixapi/tree/zabbix2.0)
* Zabbix 2.2.x (api version 2.2.x) | zabbixapi 2.2.x | [branch zabbix2.2](https://github.com/express42/zabbixapi/tree/zabbix2.2)
* Zabbix 2.4.x (api version 2.2.x) | zabbixapi 2.4.x | [branch zabbix2.4](https://github.com/express42/zabbixapi/tree/zabbix2.4)
* Zabbix 3.0.x (api version 3.0.x) | zabbixapi 3.0.x | [branch zabbix3.0](https://github.com/express42/zabbixapi/tree/zabbix3.0)
* Zabbix 3.2.x (api version 3.2.x) | zabbixapi 3.2.x | [branch zabbix3.2](https://github.com/express42/zabbixapi/tree/zabbix3.2)
* Zabbix 4.0.x (api version 4.0.x) | zabbixapi 4.1.x | [branch zabbix4.0](https://github.com/express42/zabbixapi/tree/zabbix4.0)
* Zabbix 4.2.x (api version 4.2.x) | zabbixapi 4.1.x | [branch zabbix4.0](https://github.com/express42/zabbixapi/tree/zabbix4.0)
* Zabbix 4.4.x (api version 4.4.x) | zabbixapi 4.2.x | [branch zabbix4.2](https://github.com/express42/zabbixapi/tree/zabbix4.2)

## Supported Ruby Versions
This library aims to support and is [tested against][github-ci] the following Ruby
versions:

* Ruby 2.5
* Ruby 2.6
* Ruby 2.7
* JRuby 9.2.10.0

If something doesn't work on one of these versions, it's a bug.

This library may inadvertently work (or seem to work) on other Ruby versions,
however support will only be provided for the versions listed above.

If you would like this library to support another Ruby version or
implementation, you may volunteer to be a maintainer. Being a maintainer
entails making sure all tests run and pass on that implementation. When
something breaks on your implementation, you will be responsible for providing
patches in a timely fashion. If critical issues for a particular implementation
exist at the time of a major release, support for that Ruby version may be
dropped.

## Dependencies

* net/http
* json

## Contributing

* Fork the project.
* Base your work on the master branch.
* Make your feature addition or bug fix, write tests, write documentation/examples.
* Commit, do not mess with rakefile, version.
* Make a pull request.

## Zabbix documentation

* [Zabbix Project Homepage][Zabbix]
* [Zabbix API docs][Zabbix API]

[Zabbix]: https://www.zabbix.com
[Zabbix API]: https://www.zabbix.com/documentation/5.2/manual/api

## Copyright

- Originally created by [Express 42 Team](https://express42.com/)
- Copyright (c) 2015-2021 [Express 42](https://express42.com/) and [contributors]
- Transfered to [markt-de](https://github.com/orgs/markt-de/repositories) in 2026 (see [issue #128](../../issues/128))

See [LICENSE] for details.

[LICENSE]: LICENSE.md
[contributors]: https://github.com/express42/zabbixapi/graphs/contributors
