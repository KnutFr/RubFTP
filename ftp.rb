#!/usr/bin/env ruby
require "socket"
include Socket::Constants
require 'yaml'
require 'mime/types'
#require "./errorHandler"

# Volcano FTP contants
BINARY_MODE = 0
ASCII_MODE = 1
MIN_PORT = 1025
MAX_PORT = 65534

# Volcano FTP class
class VolcanoFtp
	def initialize
		# Prepare instance 
		config = YAML.load_file('./config/config.yml')
		@usersArray = YAML.load_file('./config/account.yml')
		@host = config['server']
		port = config['port']
		@socket = TCPServer.new(@host, port)
		@socket.listen(42)

		@pids = []
		@transfert_type = BINARY_MODE
		@tsocket = nil
		@passive = true
		@currentPath = nil
		puts "Server ready to listen for clients on port #{port}"
	end

	def ftp_noop(args)
		@cs.write "200 Don't worry my lovely client, I'm here ;)"
		0
	end

	def ftp_quit(args)
		@cs.write "221 Thank you for using Volcano FTP\r\n"
		@users.delete(@cs.peeraddr[1])
		@cs.close
		-1
	end


	#
	#nos commandes 
	#Les logins sont dans account.yml 
	#

	def ftp_user(args) #Recuperation de l'username commande USER
		@user = @usersArray.find {|key| key["login"] == args.chomp }
		@cs.write "331 Please specify the password\r\n"
	end

	def ftp_pass(args) #Recuperation du password commande PASS
		if @user != nil and @user["pass"] == args.chomp
			@cs.write "230 Connection successful\r\n"
		else
			@cs.write "530 Incorrect login or password\r\n"
		end
	end

	def ftp_syst(args)
		@cs.write("215 UNIX Type: L8\r\n")
		0
	end

	def ftp_feat(args)
		@cs.write "List of implemented command: \r\n\r\nUSER 'username' - Current username \r\n"
		@cs.write "PASS 'password' - Password for current username Authentification \r\nPWD  - Return current Path \r\n"
		@cs.write "CWD 'path' - Change current Path: \r\nLIST - Return list of all file in the current Path \r\n"
		@cs.write "STOR 'filename' - Upload file in current Path \r\nRETR 'filename' - Download file \r\n"
		@cs.write "SIZE 'filename' - Return size of the file \r\nWHO - Return the list of all current user (NY) \r\n"
		@cs.write "MIMETYPE - Return mimetype of a file \r\nFEAT - Return all available featuring list\r\n"
	end

	def ftp_pwd(args) #Retourne le path du repertoire actuel commande PWD
		@cs.write "257 \"#{Dir.pwd}\"\r\n"
	end

	def ftp_type(args)
		args = args.chomp
		if args.upcase == "A"
			@cs.write "200 Type set to ASCII\r\n"
		elsif args.upcase == "I"
			@cs.write "200 Type set to binary\r\n"
		else
			@cs.write "500 Invalid type\r\n"
		end
	end


	def ftp_pasv(args)
		@cs.write "502 Command not implemented\r\n"
	end

#	def ftp_pasv(args)
#		@data_socket = nil
#		port = 1024
#		while (@data_socket == nil)
#			begin
#				port += 1
#				@data_socket = TCPSocket.new(@host,port)
#			rescue
#			end
#		end
#		if (@data_socket == nil)
#			@cs.write "425 Unable to open passive connection\r\n"
#		else
#			@passive = true
#			ip = @host.split(".")
#			port0 = port / 256
#			port1 = port % 256
#			@cs.write "227 Entering Passive Mode (" << ip[0] << "," << ip[1] << "," << ip[2] << "," << ip[3] << "," << port0.to_s << "," << port1.to_s << ")\r\n"
#		end
#	end

	def ftp_port(args)
		arguments = args.split(',')
		ip = arguments[0] + "." + arguments[1] + "." + arguments[2] + "." + arguments[3];
		port =  arguments[4].to_i * 256 + arguments[5].to_i
		begin
			@data_socket = TCPSocket.new(ip, port)
			@passive = false
			@cs.write "200 Opened active connection : port (#{port})\r\n"
		rescue Exception => e
			@cs.write "425 Unable to open active connection : #{e}\r\n"
		end
	end

	def ftp_list(args) #list le repertoire courant (PWD) command LIST
		if args == ""
			@currentPath = Dir.pwd
		else
			@currentPath = args.chomp
		end
		@cs.write "125 Here comes the directory listing of #{@currentPath.to_s}\r\n"
		Dir.entries(@currentPath).each do |file|
			if file != "." && file != ".."
				@data_socket.write file << "\r\n"
			end
		end
	    @data_socket.close()
		@cs.write "226 Files successfully listed\r\n"
	end

	def ftp_cwd(args) #Change de repertoire (cible = args) command CWD
		begin
			Dir.chdir(args.chomp)
			@cs.write "250 Directory successfully changed.\r\t"
		rescue
			@cs.write "550 Failed to change directory.\r\n"
		end
	end

	def ftp_stor(args) #Stockage du fichier dans le PWD command STOR
		args = args.chomp
		file = File.open(args, "wb")
		if file != nil
			while datas = @data_socket.gets
				file.puts datas
			end
			file.close
			@cs.write("226 File successfully uploaded\r\n")
		else
			@cs.write("550 Failed to upload the file\r\n")
		end
		@data_socket.close()
	end

	def ftp_retr(args) #Telechargement d'un fichier dont le path est l'argument commande RETR
		args = args.split("\\").last.chomp
		file = File.open(args, "rb")
		if file != nil
			while datas = file.gets
				@data_socket.puts datas
			end
			file.close
			@cs.write("226 File successfully downloaded\r\n")
		else
			@cs.write("550 Failed to download the file\r\n")
		end
		@data_socket.close()
	end

	#
	# divers
	#	

	def ftp_size(args) #Taille du fichier (utile pour les stats)
		@cs.write "200 Filesize of #{args.to_s} = #{File.size?(args).to_s} \r\n"
		return File.size?(args)
	end

	def ftp_cdup(args) #Retour dossier parent
		array = @currentPath.to_s.split("/")
		@currentPath = ""
		array.pop
		array.each do |pathItem|
			if pathItem != array.last
				@currentPath << pathItem << "/"
			else
				@currentPath << pathItem
			end
		end
		ftp_cwd(@currentPath)
	end

	def ftp_mdtm(args)
		name_file = args.split("\\")
		name_file = name_file.last.chomp
		time_file = File.ctime(name_file).to_s
		time_file = time_file.split(/[-: ]/)
		time_file = time_file[0] << time_file[1] << time_file[2] << time_file[3] << time_file[4] << time_file[5]
		@cs.write "200 Last modified date of #{args.to_s} = " << time_file << "\r\n"
		return time_file
	end

	def ftp_dele(args)
		file = @currentPath << "/" << args.chomp
		File.delete(file)
		@cs.write "200 File #{args.chomp} successfully deleted \r\n"
	end

	def ftp_rnfr(args)
		@previous_name = args.chomp
		@cs.write "200 Renaming #{args.chomp} \r\n"
	end

	def ftp_rnto(args)
		File.rename(@previous_name, args.chomp)
		@cs.write "200 File successfully renamed as #{args.chomp} \r\n"
	end

	def ftp_who(args) #Retourne le nombre de personne connecté
		@cs.write "200 #{@users.size} persons currently connected \r\n"
	end

	def ftp_mimetype(args) #Retourne le mimetype d'un file
		@cs.write "200 Command Okay \r\n"
		@cs.write "MIMETYPE of file #{args.to_s} is #{MIME::Types.type_for(args)}\r\n"
	end


	#
	# gestion du serveur
	#

	def ftp_usage(args)
		@cs.write "Usage: volcano_ftp.rb start|stop|restart|status"
	end

	def ftp_start(args)
		@cs.write "Starting Server"
		@cs.write "Server started"
	end

	def ftp_stop(args)
		@cs.write "Stopping Server"
		@cs.write "Server stopped"
	end

	def ftp_restart(args)
		@cs.write "Restarting Server"
		@cs.write "Server stopped"
		@cs.write "Server started"
	end

	def ftp_status(args)
		@cs.write "Status server"
	end


	#
	#Gestion des stats
	#

	def logConnexion
	end


	#
	#divers
	#

	def parseCommand(commands)
		tabParams = commands.split(' ', 2)
		myCommand = tabParams[0].downcase
		if myCommand
			myPtr = "ftp_" + myCommand.to_s
		end
		if self.respond_to?(myPtr)
			self.send(myPtr, tabParams[1])
		else
			ftp_502(tabParams[1])
		end
	end

	def run # SERVER-PI #
		pidCount = 0
		while (42)
			selectResult = IO.select([@socket], nil, nil, 1)
			if selectResult == nil or selectResult[0].include?(@socket) == false
				@pids.each do |pid|
					if not pid.alive?
						puts pid.inspect
						@pids.delete(pid)
					end
				end
				if @pids.count != pidCount
					pidCount = @pids.count
					p @pids
				end
			else
				@cs, = @socket.accept
				peeraddr = @cs.peeraddr.dup
				@pids << Thread.new {
					puts "[#{Process.pid}] Instanciating connection from #{@cs.peeraddr[2]}:#{@cs.peeraddr[1]}"
					@cs.write "220-\r\n\r\n Welcome to Volcano FTP server !\r\n\r\n220 Connected\r\n"
					while not (line = @cs.gets).nil?
						puts "[#{Process.pid}] Client sent : --#{line}--"
						parseCommand(line);
					end
					puts "[#{Process.pid}] Killing connection from #{peeraddr[2]}:#{peeraddr[1]}"
					@cs.close
				}
			end
		end
	end

	protected
	  # Protected methods go here
	end

	# Main
	begin
		ftp = VolcanoFtp.new
		ftp.run
	rescue SystemExit, Interrupt
		puts "Caught CTRL+C, exiting"
	rescue RuntimeError => e
		puts e
	end