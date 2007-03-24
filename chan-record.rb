#!/usr/bin/env ruby

#require 'kconv'
#require 'socket'

require 'date'
require 'time'
#require 'breakpoint'

RECORD = "cat"
DVR = "/dev/dvb/adapter0/dvr0"
AZAPCHANFILE = "/home/jeremy/.azap/channels.conf"

class Recording
	RECORDING = 0
	IDLE = 1
	CRASHED = 2	  
	
	def initialize( channel = "test" )
		@channel = channel
		@status = 1
		@crashcount = 0
	end

	def record (dvr, file)
		@recordingdevice = dvr
		@recordingfile = file
		@status = RECORDING
                @child = fork {
			cmdstr = "cat #{@recordingdevice} 1> #{@recordingfile} 2> /tmp/cat.error"
			exec cmdstr
		}
	end
	
	def stop
		if @status == RECORDING then Process.kill(15,@child) 
		else
			Process.wait(@child)
		end
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
	
	def schedule( startdatetime, stopdatetime, dvr, file = 'default.mkv' )
		@startdt = DateTime.parse(startdatetime)
		@stopdt = DateTime.parse(stopdatetime)
		while @status == IDLE
			sleep 1
			if( DateTime.now < @startdt )
				record(dvr,file)
			end
		end
		while @status == RECORDING
			sleep 1
			if DateTime.now < @stopdt
				stop
			end
		end
		return true
	end
		
				
			
			
	
end


if ARGV[0]
  name = ARGV[0]
  vcr = Recording::new(name)
  vcr.record(DVR,"#{name}.mkv")
  while vcr.get_status != 1
	sleep 1
  end
end