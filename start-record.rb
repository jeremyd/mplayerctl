#!/usr/bin/ruby
require 'drb/drb'

SERVER_URI = "druby://localhost:8989"

if ARGV[0]
  name = ARGV[0]
  recording = DRbObject.new_with_uri(SERVER_URI) 
  recording.record(name)
	puts "recording started"
end

