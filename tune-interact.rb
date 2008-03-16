#!/usr/bin/ruby
=begin
This program is part of chan-record.rb

chan-record.rb is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program.  If not, see <http://www.gnu.org/licenses/>.
=end


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
