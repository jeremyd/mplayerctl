require 'drb/drb'

DVR = "/dev/dvb/adapter0/dvr0"
SERVER_URI = "druby://localhost:8989"
DRb.start_service

if ARGV[0]
  name = ARGV[0]
  recording = DRbObject.new_with_uri(SERVER_URI) 
  recording.record(DVR,"#{name}.mkv")
end

