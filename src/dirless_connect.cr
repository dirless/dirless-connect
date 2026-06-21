require "./dirless/connect/config"
require "./dirless/connect/keypairs"
require "./dirless/connect/commands/ssh_register"
require "./dirless/connect/commands/ssh_login"

module Dirless
  module Connect
    VERSION = "0.0.6"

    def self.usage : Nil
      STDERR.puts <<-USAGE
        dirless-connect #{VERSION}

        Usage:
          dirless-connect ssh register   One-time setup: generate keys, send magic link
          dirless-connect ssh login      Obtain a short-lived SSH certificate
          dirless-connect version        Print version and exit

        Environment:
          DIRLESS_OPS_URL    Override the ops API URL (default: https://admin.dirless.com)

        USAGE
    end

    def self.run(args : Array(String)) : Int32
      transport = args[0]?
      subcommand = args[1]?

      case transport
      when "ssh"
        case subcommand
        when "register"
          Commands::SshRegister.new.run(args[2..])
        when "login"
          Commands::SshLogin.new.run(args[2..])
        else
          STDERR.puts "Unknown ssh subcommand: #{subcommand || "(none)"}"
          STDERR.puts "Available: register, login"
          1
        end
      when "version", "--version", "-v"
        STDOUT.puts "dirless-connect #{VERSION}"
        0
      when nil, "--help", "-h", "help"
        usage
        0
      else
        STDERR.puts "Unknown command: #{transport}"
        usage
        1
      end
    end
  end
end

exit Dirless::Connect.run(ARGV)
