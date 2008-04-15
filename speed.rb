#!/usr/bin/ruby
require 'drb/drb'


SERVER_URI = "druby://localhost:6767"
x=DRbObject.new_with_uri(SERVER_URI)
puts x.speed_set(ARGV[0])
