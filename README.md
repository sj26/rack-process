# Rack::Process

Proxy to a rack application in a separate process.

[An issue](https://github.com/37signals/pow/issues/136) filed for pow piqued my curiosity. After itching, this is what I came up with.

## Usage

You can't run multiple rails applications in the same process. Instead, we can load those applications in separate processes and compose them using Rack.

Here's a simple example `config.ru` which does just that:

```ruby
require 'rack'
require 'rack-process'

run Rack::URLMap.new \
  "/first" => Rack::Process.new('/path/to/rails-app-1'),
  "/second" => Rack::Process.new('/path/to/rails-app2')
```

## Thanks

 * @josh's excellent [nack](https://github.com/josh/nack) used by [pow](https://github.com/37signals/pow).
 * @tpope for [Ruby IO Mixins](http://git.tpope.net/ruby-io-mixins.git).
 * Daniel J. Bernstein for [netstrings](http://cr.yp.to/proto/netstrings.txt), and @josh for nack's implementation.

## Contributing

1. Fork it
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Added some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create new Pull Request
