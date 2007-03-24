#!/usr/bin/env ruby

#require 'kconv'
#require 'socket'

require 'date'
require 'time'
require 'drb/drb'
URI="druby://localhost:8989"

RECORD = "cat"
DVR = "/dev/dvb/adapter0/dvr0"
AZAPCHANFILE = "/home/jeremy/.azap/channels.conf"

class Recording
	RECORDING = 0
	IDLE = 1
	CRASHED = 2	  
	include DRb::DRbUndumped
	def initialize( channel = "test" )
		@channel = channel
		@status = 1
		@crashcount = 0
		@catpid = 0
	end

	def record (dvr, file)
		@recordingdevice = dvr
		@recordingfile = file
		@status = RECORDING
                @child = fork {
			cmdstr = "cat #{@recordingdevice} 1> #{@recordingfile} 2> /tmp/cat.error"
			exec cmdstr
		}
		@catpid = `ps auxww |grep #{@recordingdevice}`
		
	end
	
	def stop
		#if @status == RECORDING then 
		Process.kill(15,@child) 
		#else
		Process.wait(@child)
		#end
		`killall cat`
		@status = IDLE unless @status == CRASHED
        end

	def get_status
		if File.exists? "/tmp/cat.error"
			x=File.open("/tmp/cat.error","r")
			case x.gets
				when /Value too large for defined data type/
				x.close
				File.delete("/tmp/cat.error")
				stop
				@status = CRASHED
				resume
				when /Device or resource busy/
				x.close
				File.delete("/tmp/cat.error")
				stop
				when /exited/
				x.close
				File.delete("/tmp/cat.error")
				stop
			end
		end
		return @status
	end
	
	def resume
		if @status == CRASHED
			@crashcount = @crashcount + 1
			record(@recordingdevice,"#{@channel}-#{@crashcount}-recovery.mkv")
			return true
		else
			return false
		end
	end
	
end

recordingcontrol = Recording::new
FRONT_OBJECT = recordingcontrol
DRb.start_service(URI, FRONT_OBJECT)
DRb.thread.join

=begin
if ARGV[0]
  name = ARGV[0]
  vcr = Recording::new(name)
  vcr.record(DVR,"#{name}.mkv")
  while vcr.get_status != 1
	sleep 1
  end
end
=end
