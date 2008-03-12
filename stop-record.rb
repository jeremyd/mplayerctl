#!/usr/bin/ruby
require 'drb/drb'

DVR = "/dev/dvb/adapter0/dvr0"
SERVER_URI = "druby://localhost:8989"
recording = DRbObject.new_with_uri(SERVER_URI)  
recording.stop

