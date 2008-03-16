#!/usr/bin/env ruby
require 'rubygems'
require 'drb/drb'
require 'date'
require 'time'
require 'chronic'
require 'ruby-debug'

URI="druby://localhost:8989"

class Recording
  RECORDING = 0
  IDLE = 1
  CRASHED = 2	
  QUIT = 3
  RETUNE = 4  
  
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
  
  def add_action(action, chronictime)
    @actions.push :action => action, :chronictime => chronictime
    puts "#{action} scheduled for #{Chronic.parse(chronictime)}"
  end
  
  def action_watchdog
    @actions.each do |a|
      set_time = Chronic.parse(a[:chronictime])
      now_time = Time.now
      if set_time <= now_time
        to_run = a[:action]
        puts "running action: #{to_run}"
        eval(to_run)
      end
    end
  ensure
    @actions.reject! do |r|
      datestr, timestr = r[:time].split(/[@]/)
      set_time = Time.parse(timestr)
      set_date = Date.parse(datestr)
      now_time = Time.now
      now_date = Date.today
      set_date == now_date && set_time <= now_time
    end
    if @status == RECORDING
      puts 'warning: process reported recording was not happening' unless 
        is_recording?
    end
  end
  
  def tune(chan)
    if @status == RECORDING
      stop
      @status = RETUNE
    end
    Process.kill(15,@tune) unless @tune.nil?
    sleep(1)
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
    stop if @status == RECORDING
    @basename = file.dup
    @basename.gsub!(/-[0-9]+?-recovery/,"")
    @basename.gsub!(/#{File.extname(file)}/,"")
    @recordingdevice
    @recordingfile = file
    puts "now recording to: #{@recordingfile}"
    @status = RECORDING
    
    @child = Process.fork {
      begin
      File.open(@recordingfile,"w") do |recordfile|
        File.open(@recordingdevice,"r") do |dev|
          while 1
            recordfile.write dev.readpartial(2000000)
          end
        end
      end
      rescue => e
        STDOUT.puts "Recording process encountered an error => #{e}"
      end
    }
    Thread.new { wait_and_resume }
    Process.fork { 
      while(1) do
        sleep(5)
        break if !is_recording?
      end
      puts "WARNING: recording to #{@recordingfile} is not happening"
      }
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
  
  def is_recording?
    test_size = File.size(@recordingfile)
    sleep(5)
    new_size = File.size(@recordingfile)
    return false if new_size == test_size
    return true
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