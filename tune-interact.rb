#!/usr/bin/ruby
require 'drb/drb'

def azap_config_interactive(conf)    
  conf.each_with_index do |a,i|
    puts "#{i}) #{a}"
  end
  puts "Please enter a channel # and hit return>"
  input = STDIN.readline
  begin
    chanline = conf.to_a[input.to_i]
    chan = chanline.split(/:/)[0]
    return chan unless chan.nil?
  rescue => e
    puts e
    return nil
  end
end

SERVER_URI = "druby://localhost:8989"
recording = DRbObject.new_with_uri(SERVER_URI)
tune_to = azap_config_interactive(recording.azapconfig)
puts "Changing channel to: #{tune_to}"
recording.tune(tune_to) unless tune_to.nil?