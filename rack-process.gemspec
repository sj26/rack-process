# -*- encoding: utf-8 -*-
require File.expand_path('../lib/rack/process/version', __FILE__)

Gem::Specification.new do |gem|
  gem.authors       = ["Samuel Cochran"]
  gem.email         = ["sj26@sj26.com"]
  gem.description   = %q{Proxy to a rack app in a seperate process.}
  gem.summary       = %q{Proxy to a rack app in a seperate process.}
  gem.homepage      = "http://github.com/sj26/rack-process"

  gem.executables   = `git ls-files -- bin/*`.split("\n").map{ |f| File.basename(f) }
  gem.files         = `git ls-files`.split("\n")
  gem.test_files    = `git ls-files -- {spec}/*`.split("\n")
  gem.name          = "rack-process"
  gem.require_paths = ["lib"]
  gem.version       = Rack::Process::VERSION

  gem.add_development_dependency "rspec", "~> 2.9"
end
