=begin
This is a DRb client to provide a persistant interface to the MPlayer-server class.
=end

require 'drb/drb'

class MPlayerClient
	SERVER_URI = "druby://localhost:8787"
	include DRb::DRbUndumped
	def initialize
		DRb.start_service
		@player=DRbObject.new_with_uri(SERVER_URI)
	end
	def play
		@player.play
	end
	def load_playlist(playlist)
		@player.load_playlist(playlist)
	end
	def stop
		@player.stop
	end
end
