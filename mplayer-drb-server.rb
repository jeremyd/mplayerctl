#!/usr/bin/env ruby

=begin

 Ruby library for MPlayer( Ruby/MPlayer)

 (c) Copyright 2004 Kazuki Takemura(kyun@key.kokone.to), japan.
 All rights reserverd.

    Redistribution and use in source and binary forms, with or without
    modification, are permitted provided that the following conditions
    are met:
    1. Redistributions of source code must retain the above copyright
       notice, this list of conditions and the following disclaimer as
       the first lines of this file unmodified.
    2. Redistributions in binary form must reproduce the above copyright
       notice, this list of conditions and the following disclaimer in the
       documentation and/or other materials provided with the distribution.

    THIS SOFTWARE IS PROVIDED BY Kazuki Takemura ``AS IS'' AND ANY EXPRESS OR
    IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES
    OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED.
    IN NO EVENT SHALL Kazuki Takemura BE LIABLE FOR ANY DIRECT, INDIRECT,
    INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT
    NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
    DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
    THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
    (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF
    THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

=end

require 'kconv'
require 'socket'
require 'drb/drb'
require 'optparse'
URI = "druby://localhost:6767"

class MPlayer

  INACTIVE  = 0
  READY     = 1
  PLAY      = 2
  PAUSED    = 3
  LIVE      = 4
  RESUME    = 5
  RECOVERY = 6

  def initialize(mplayercmd, addopts = "")
    @mplayerpath = mplayercmd
    @status = MPlayer::INACTIVE
    @addopts = addopts
    @type = 'unknown'
    @bitrate = 'unknown'
    @title = 'unknown'
    @artist = 'unknown'
    @album = 'unknown'
    @channel = 'unknown'
    @curfilesize = 0
    @livedelay = 5
    @crashcount = 1
  end

  def load(video)
    stop if @status == PLAY || @status == PAUSED
    @playlistfile = video
    @status = MPlayer::READY
    @mplayeropts = "-slave " + @addopts
    if video =~ /-([0-9]+?)-recovery/
      @crashcount = $1.to_i + 1
      @extname = File.extname(@playlistfile)
      @basename = video.gsub(/-[0-9]+?-recovery#{File.extname(@playlistfile)}/,"")
    else               
      @basename = video.gsub(/#{@extname}/,"")
    end
  end

  def resumelive
    puts "resuming Live TV"
    @status = LIVE
    @curfilesize = File.size(@playlistfile)
    sleep(@livedelay)
    play
  end

  def play
    if @status == READY || @status == LIVE || @status == RESUME || @status == RECOVERY
      @receive, send = Socket::pair(Socket::AF_UNIX, Socket::SOCK_STREAM, 0)
      receive, @send = Socket::pair(Socket::AF_UNIX, Socket::SOCK_STREAM, 0)
      @file = ''
      @type = 'unknown'
      @bitrate = 'unknown'
      @title = 'unknown'
      @artist = 'unknown'
      @album = 'unknown'
      @channel = 'unknown'
      @child = fork {
        @send.close
        @receive.close
        STDIN.reopen( receive)
        STDOUT.reopen( send)

        case @status
        when LIVE
          cmdstr = "#{@mplayerpath} #{@mplayeropts} -sb #{@curfilesize} #{@playlistfile}"
        when RECOVERY
          cmdstr = "#{@mplayerpath} #{@mplayeropts} #{@playlistfile}"
        else
          cmdstr = "#{@mplayerpath} #{@mplayeropts} #{@playlistfile}"
        end
        exec cmdstr
      }
      send.close
      receive.close
      @status = PLAY
      @lastmsg = @receive.readline
      start_inspector
      return true
    else
      return false
    end
  end

  def stop
    if @status == PLAY || @status == PAUSED
      stop_inspector
      @send.write("quit\n")
      Process::waitpid( @child, 0)
      @send.close
      @receive.close
      @status = READY
      return true
    else
      return false
    end
  end

  def pause
    if @status == PLAY || @status == PAUSED
      @send.write("pause\n")
      if @status == PLAY
        @status = PAUSED
      else
        @status = PLAY
      end
      return true
    else
      return false
    end
  end

  def playlist( step)
    if @status == PLAY || @status == PAUSED
      #@playfile = ''
      str = "pt_step #{step}\n"
      @send.write(str)
      return true
    else
      return false
    end
  end

  def playlist_next
    playlist(1)
  end

  def playlist_prev
    playlist(-1)
  end

  def seek( step)
    if @status == PLAY || @status == PAUSED
      str = "seek #{step}\n"
      @send.write(str)
      return true
    else
      return false
    end
  end

  def get_status
    return @status
  end

  def get_fileinfo
    return @playfile, @type, @bitrate, @channel, @title, @artist, @album
  end

  def start_inspector
    stop_inspector
    @polling_thread = Thread::start{
    while true
      @lastmsg = @receive.readline
      @lastmsg.chop!
      case @lastmsg
        when /^Playing (.+)/
          @playfile = $1
          @playfile.gsub!(/\.$/,'')
          @type = 'unknown'
          @bitrate = 'unknown'
          @title = 'unknown'
          @artist = 'unknown'
          @album = 'unknown'
          @channel = 'unknown'
          #print "file: #{@playfile}\n"
        when /^ Title: (.+)/
          @title = $1.toeuc
          #print "title: #{@title}\n"
        when /^ Artist: (.+)/
          @artist = $1.toeuc
          #print "artist: #{@artist}\n"
        when /^ Album: (.+)/
          @album = $1.toeuc
          #print "album: #{@album}\n"
        when /^Selected audio codec: \[(.+?)\] (.+)$/
          @type = $1
          #print "type: #{@type}\n"
        when /^AUDIO: (\d+) Hz, (\d) ch,(.+)\((.*?) kbit\)$/
          @channel = $2
          @bitrate = $4
          #print "channel: #{@channel}, bitrate: #{@bitrate}\n"
        when /^Exiting\.\.\. \(End of file\)/
          print "Mplayer Thread Exited. EOF\n"

          if is_currently_recording 
            @status = MPlayer::LIVE
          elsif File.exists?("#{@basename}-#{@crashcount}-recovery#{@extname}")
            @status = MPlayer::RECOVERY
          else
            @status = MPlayer::READY
          end
          stop_inspector
          @send.close
          @receive.close
        when /^Exiting\.\.\./
          print "Mplayer Thread Exited.\n"
          @status = MPlayer::READY
          stop_inspector
          @send.close
          @receive.close
        end
        print ">>#{@lastmsg}\n"
      end 
    }
  end

  def recover
    if @status == MPlayer::RECOVERY
      puts "recovering from crash.. #{@basename}-#{@crashcount}-recovery.#{@extname}\n\n"
      @playlistfile = "#{@basename}-#{@crashcount}-recovery#{@extname}"
      @crashcount = @crashcount +1
      play
    end
  end

  def stop_inspector
    @polling_thread.exit if !@polling_thread.nil? && @polling_thread.alive?
  end

  def is_currently_recording
    @test_size = File.size(@playlistfile)
    sleep(1)
    @new_size = File.size(@playlistfile)
    if @new_size == @test_size
      return false
    else
      return true
    end
  end
  
end

# MAIN
options = { :mplayer => `which mplayer`.chomp, :mplayer_opts => "-cache 7000 -quiet -fs" }
USAGE = "Usage: mplayer-ctl-hdtv.rb -f filename [--nvidia] [--xwinwrap path-to-xwinwrap] [--mplayer path-to-mplayer] [--options mplayer_options]\n"
OptionParser.new do |opts|
  opts.banner = USAGE
  opts.on("-n", "--nvidia") do |nv|
    options[:mplayer_opts] = "-vo xvmc,xv -vc ffmpeg12mc -cache 7000 -quiet -fs"
  end
  opts.on("-m", "--mplayer", "=PATH") do |m|
    options[:mplayer] = m
  end
  opts.on("-o", "--options", "=OPTIONS") do |o|
    options[:mplayer_opts] = o
  end
  opts.on("-x", "--xwinwrap", "=PATH") do |x|
    mplay = options[:mplayer].dup
    xwinwrap = x
    options[:mplayer] = "#{xwinwrap} -ni -o 0.9 -fs -s -st -sp -b -nf -- #{mplay}"
    options[:mplayer_opts] = "-wid WID -cache 7000 -slave -fs"
  end
  opts.on("--f", "filename", "=PATH") do |f|
    options[:filename] = f
  end  
end.parse!

raise USAGE unless options[:filename]

mplayerpersistant = MPlayer.new(options[:mplayer],options[:mplayer_opts])
FRONT_OBJECT = mplayerpersistant
puts options[:filename]
mplayerpersistant.load(options[:filename])
mplayerpersistant.play
DRb.start_service(URI, FRONT_OBJECT)
while @status != MPlayer::READY
  @status = mplayerpersistant.get_status
  sleep 1
  mplayerpersistant.resumelive if @status == MPlayer::LIVE
  mplayerpersistant.recover if @status == MPlayer::RECOVERY
end