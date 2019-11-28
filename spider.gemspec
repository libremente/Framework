require 'date'

Gem::Specification.new do |s|
  s.name     = "spiderfw"
  s.version  = File.read(File.dirname(__FILE__)+'/VERSION')
  s.date     = File.mtime("VERSION").strftime("%Y-%m-%d")
  s.summary  = "A (web) framework"
  s.email    = "abmajor7@gmail.com"
  s.homepage = "http://github.com/me/spider"
  s.description = "Spider is yet another Ruby framework."
  s.has_rdoc = true
  s.authors  = ["Ivan Pirlik"]
  s.files = [
      'README.rdoc',
      'VERSION',
      'CHANGELOG',
      'Rakefile',
      'spider.gemspec'] \
      + Dir.glob('apps/**/*') \
      + Dir.glob('bin/*') \
      + Dir.glob('blueprints/**/*', File::FNM_DOTMATCH) \
      + Dir.glob('data/**/*') \
      + Dir.glob('lib/**/*.rb') \
      + Dir.glob('views/**/*') \
      + Dir.glob('public/**/*') \
      + Dir.glob('templates/**/*')
#  s.test_files = []
#  s.rdoc_options = ["--main", "README.rdoc"]
#  s.extra_rdoc_files = ["CHANGELOG", "LICENSE", "README.rdoc"]
  s.executables = ['spider']
  s.default_executable = 'spider'
  s.add_dependency("cmdparse", ["> 2.0.0"])
  s.add_dependency("fast_gettext", [">= 0.5.13"])
  s.add_dependency("hpricot", ["> 0.8"])
  s.add_dependency("json_pure", ["> 1.1"])
  s.add_dependency("uuidtools", ["> 2.1"])
  s.add_dependency("rufus-scheduler", ["> 1.0"])
  s.add_dependency("mime-types", ["> 1.0"])
  s.add_dependency("locale", ["> 2.0"])
  s.add_dependency("builder", ["> 2.1"])
  s.add_dependency("macaddr", [">= 1.0.0"])
  s.add_dependency("bundler")
  s.add_dependency("mail")
  s.add_dependency("backports")
  s.add_dependency("rack")
  s.add_development_dependency("rake", ["> 0.7.3"])
  s.add_development_dependency("gettext", ['>= 2.1.0'])
  if RUBY_VERSION >= '1.9'
    s.add_development_dependency("celluloid")
    s.add_development_dependency("listen")
  else
    s.add_development_dependency("fssm")
  end
  s.requirements << "Optional dependencies: ripl, ripl-irb, ripl-multi_line, json, openssl, sqlite3, mongrel, ruby-oci8 >2.0, mysql, yui-compressor, cldr"
  # optional dependencies
  # 
end
