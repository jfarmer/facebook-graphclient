spec = Gem::Specification.new do |s|
  s.name = 'facebook-graphclient'
  s.version = '0.3'
  s.date = '2010-12-12'
  s.summary = "A simple library for Facebook's new Graph API"
  s.description = "A bare-bones implementation of Facebook's new Graph API"

  s.homepage = "http://github.com/jessefarmer/facebook-graphclient"

  s.authors = ["Jesse Farmer"]
  s.email = "jesse@bumbalabs.com"

  s.add_dependency('yajl-ruby')
  s.add_dependency('patron')
  
  # TODO Remove this dependency
  s.add_dependency('rack')
  s.has_rdoc = false

  s.files = ["README",
  "facebook-graphclient.gemspec",
  "lib/facebook-graphclient.rb",
  "lib/facebook-graphclient/rails.rb"]
end
