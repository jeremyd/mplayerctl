#!/usr/bin/env ruby
require 'rubygems'
require 'drb/drb'
require 'date'
require 'time'
require 'ruby-debug'

URI="druby://localhost:8989"

class Recording
  RECORDING = 0
  IDLE = 1
  CRASHED = 2	
  QUIT = 3
  RETUNE = 4
 # include DRb::DRbUndumped  
  
  def initialize(dvr = nil, azapconfig = nil, azapcmd = nil)
    dvr ||= "/dev/dvb/adapter0/dvr0"
    @recordingdevice = dvr
    azapconfig ||= "#{ENV['HOME']}/.azap/channels.conf"
    @azapconfig = IO.read(azapconfig)
    azapcmd ||= "azap"
    @azapcmd = azapcmd
    @status = IDLE
    @crashcount = 0
    @actions = []
    puts @azapconfig
  end
  
  def add_action(action, time)
    @actions.push :action => action, :time => Time.parse(time)
    puts "#{action} scheduled for #{Time.parse(time)}"
  end
  
  def action_watchdog
    set_time = Time.now
    @actions.each do |a|
      if set_time > a[:time]
        to_run = a[:action]
        puts "running action: #{to_run}"
        eval(to_run)
      end
    end
  ensure
    @actions.reject! do |r|
      set_time > r[:time]
    end
  end
  
  def tune(chan)
    if @status == RECORDING
      stop
      @status = RETUNE
    end
    Process.kill(15,@tune) unless @tune.nil?
  ensure
    @tune = Process.fork {
      STDOUT.close
      STDIN.close
      #STDERR.close
      exec @azapcmd, '-r', chan
    }
    Process.detach(@tune)
    sleep(1)
    
    resume if @status == RETUNE 
  end

  def record(file)
    @basename = file.dup
    @basename.gsub!(/-[0-9]+?-recovery/,"")
    @basename.gsub!(/#{File.extname(file)}/,"")
    @recordingdevice
    @recordingfile = file
    puts "now recording to: #{@recordingfile}"
    @status = RECORDING
    @child = Process.fork {
      STDOUT.reopen(@recordingfile)
      STDIN.reopen(@recordingdevice)
      STDERR.reopen('/tmp/cat.error',"a")
      exec 'cat'
    }
    Thread.new { wait_and_resume }
  end
  
  def wait_and_resume
    Process.wait2(@child)
    unless @status == IDLE
      @status = CRASHED
      resume
    end
  end

  def stop
    @status = IDLE
    Process.kill(15, @child)
    Process.wait2(@child)
  rescue
    puts "the process was gone"
  end

  def get_status
    return @status
  end
 
  def resume
    if @status == CRASHED || @status == RETUNE
      @crashcount = @crashcount + 1
      record("#{@basename}-#{@crashcount}-recovery.mkv")
    end
  end
  
  def quit
    stop
    @status = Recording::QUIT
  end

end

##
## Main Loop, listen for DRb commands
##

recordingcontrol = Recording::new
FRONT_OBJECT = recordingcontrol
DRb.start_service(URI, FRONT_OBJECT)
DRb.thread.join

=begin
if ARGV[0]
  name = ARGV[0]
  recordingcontrol.record(DVR,"#{name}.mkv")
end

while(1) do
  sleep(1)
  break if recordingcontrol.get_status == Recording::QUIT
end
exit(0)
=end