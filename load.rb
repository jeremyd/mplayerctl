#!/usr/bin/ruby
require 'drb/drb'

SERVER_URI = "druby://localhost:6767"
x=DRbObject.new_with_uri(SERVER_URI)
x.load ARGV[0]
x.play
