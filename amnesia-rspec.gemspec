# -*- encoding: utf-8 -*-
$:.push File.expand_path("../lib", __FILE__)
require "amnesia-rspec/version"

Gem::Specification.new do |s|
  s.name        = "amnesia-rspec"
  s.version     = Amnesia::Rspec::VERSION
  s.authors     = ["Chris Williams"]
  s.email       = ["chris@wellnessfx.com"]
  s.homepage    = ""
  s.summary     = %q{Forked up in-memory testing}
  s.description = %q{Makes running tests less painful than stabbing yourself in the eyes}

  s.rubyforge_project = "amnesia-rspec"

  s.files         = `git ls-files`.split("\n")
  s.test_files    = `git ls-files -- {test,spec,features}/*`.split("\n")
  s.executables   = `git ls-files -- bin/*`.split("\n").map{ |f| File.basename(f) }
  s.require_paths = ["lib"]

  # specify any dependencies here; for example:
  # s.add_development_dependency "rspec"
  s.add_runtime_dependency "cod", '0.6.0'
  s.add_runtime_dependency "oj", '>= 2.9.9'
  s.add_runtime_dependency "unicorn", '4.0.1'
  s.add_runtime_dependency "rspec-core", '~> 2.9'
  s.add_runtime_dependency "capybara-webkit", '>= 0.13'
end
