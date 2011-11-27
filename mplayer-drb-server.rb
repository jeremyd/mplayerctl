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
URI = "druby://0.0.0.0:6767"

class MPlayer

  INACTIVE  = 0
  READY     = 1
  PLAY      = 2
  PAUSED    = 3
  LIVE      = 4
  RESUME    = 5
  RECOVERY = 6
  
  attr_accessor :playlist, :status

  def initialize(mplayercmd, addopts = "")
    @status = MPlayer::READY
    @mplayerpath = mplayercmd
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
    @playlist = []
  end

  def load(video)
    stop if @status == PLAY || @status == PAUSED
    @playlistfile = video
    @status = MPlayer::READY
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
      if !@playlist.empty?
        File.open("/tmp/playlistfile", "w") do |f|
          f.write @playlist.join("\n") 
        end
        @playlist = []
        @playthisnow = "-playlist /tmp/playlistfile"
      else
        @playthisnow = "'#{@playlistfile}'"
      end
      @child = fork {
        @send.close
        @receive.close
        STDIN.reopen( receive)
        STDOUT.reopen( send)
        cmdstr = "#{@mplayerpath} #{@addopts} #{@playthisnow}"
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
  
  # frame_step or slow motion
  def speed_set(value)
    if @status == PLAY || @status == PAUSED
      @send.write("speed_set #{value}\n")
    end
  end

  def frame_step
    @status = PAUSED
    @send.write("frame_step\n")
  end

  def volume(vol)
    @send.write("volume #{vol}\n")
  end

  def pt_step( step)
    if @status == PLAY || @status == PAUSED
      str = "pt_step #{step}\n"
      @send.write(str)
      return true
    else
      return false
    end
  end

  def playlist_next
    pt_step(1)
  end

  def playlist_prev
    pt_step(-1)
  end

  # String p = The name of the media to enqueue
  def enqueue(p)
    @playlist << p
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
          @status = MPlayer::READY
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

  def stop_inspector
    @polling_thread.exit if !@polling_thread.nil? && @polling_thread.alive?
  end

end

# MAIN
options = { :mplayer => `which mplayer`.chomp, :mplayer_opts => "-cache 30000 -slave -quiet -fs" }
USAGE = "\n\nUsage: mplayer-ctl-hdtv.rb [-f media file/url] [--xwinwrap path-to-xwinwrap] [--mplayer path-to-mplayer] [--options mplayer_options]\n"
OptionParser.new do |opts|
  opts.banner = USAGE
  opts.on("-a", "--altscreen") do
    options[:mplayer_opts] += " -geometry +1920+1080"
  end
  opts.on("-m", "--mplayer", "=PATH") do |m|
    options[:mplayer] = m
  end
  opts.on("-o", "--options", "=OPTIONS") do |o|
    options[:mplayer_opts] = o
  end
  opts.on("-x", "--xwinwrap", "=PATH") do |xwinwrap|
    options[:xwinwrap] = "#{xwinwrap} -ni -o 0.9 -fs -s -st -sp -b -nf --"
    options[:xwinwrap_opts] = "-wid WID -cache 7000 -slave -quiet"
  end
  opts.on("-f", "--file", "=PATH") do |f|
    options[:filename] = f
  end  
end.parse!

if options[:xwinwrap]
  MPLAYER_CMD = "#{options[:xwinwrap]} #{options[:mplayer]}"
  options[:mplayer_opts] = options[:xwinwrap_opts]
else
  MPLAYER_CMD = "#{options[:mplayer]}"
end

mplayerpersistant = MPlayer.new(MPLAYER_CMD, options[:mplayer_opts])
FRONT_OBJECT = mplayerpersistant
if options[:filename]
  mplayerpersistant.load(options[:filename])
  mplayerpersistant.play
end
DRb.start_service(URI, FRONT_OBJECT)

puts "Listening on #{DRb.uri}"

##
## Example: Simple loop to perform custom actions on status. 

while 1
  @status = mplayerpersistant.get_status
  sleep 1
  mplayerpersistant.play if @status == MPlayer::READY && !mplayerpersistant.playlist.empty?
end

#DRb.thread.join
