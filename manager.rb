#!/usr/bin/env ruby
# encoding: utf-8
require 'open3'
require 'yaml'

LIST_COMMAND = ["usage", "start", "stop", "restart", "status"]

def srv_usage
	puts "Usage: Manage_SRV.rb start|stop|restart|status"
end

def srv_status
	if @check == true
		WhatPid()
		puts "Server Volcano_ftp is running"
		puts "The PID of the serveur process is #{@PidProc[0]}"
	else
		puts "Server Volcano_ftp is not running"
	end
end

def srv_start
	puts "Starting Server"
 	system 'ruby.exe' , 'C:\Volcano_ftp\volcano_ftp.rb'
end

def srv_stop
	puts "Stopping Server"
	WhatPid()
	Open3.capture3 ("wmic process where processid=#{@PidProc[0]} terminate")
	puts "Server stopped"
end

def srv_restart
	if @check == true
		puts "Restarting Server"
		srv_stop
		srv_start
	else
		puts "Server Volcano_ftp is not running"
	end
end

def WhatPid
	@PidProc = @Stout.split("volcano_ftp.rb")
	@PidProc = @PidProc[1].split
end

def IsProcessRunning
	@Stout,stderr,status = Open3.capture3 ('wmic Process where (Name="ruby.exe") GET commandline, processid')
	@St = @Stout.split
	@check = @St.include? 'C:\\Volcano_ftp\\volcano_ftp.rb'
end
# Main
	begin

		IsProcessRunning()
		if ARGV[0] == nil
			myCommand = "start"			
		else	
			myCommand = ARGV[0].downcase
		end

		if (LIST_COMMAND.index(myCommand))
			if @check != false && myCommand == "start"
				puts "Server is starting already!"
			elsif @check == false && myCommand == "stop"
				puts "Server is not starting"	
			else
				Mycmd = "srv_" + myCommand.to_s
				self.send(Mycmd)
			end
		else
			puts "Command '#{myCommand.to_s}' not found"
			srv_usage
		end
		
		rescue SystemExit, Interrupt
		puts "Caught CTRL+C, exiting"
		rescue RuntimeError => e
		puts e	
	end