require "age-crystal"
require "./config"

module Dirless
  module Connect
    # Manages the two keypairs that dirless-connect owns on behalf of the user.
    # Users never touch these directly — this module is the sole owner.
    module Keypairs
      # Generates the age identity file if it doesn't exist yet.
      # Returns the public key string (age1...).
      def self.ensure_age_key : String
        if File.exists?(Config::AGE_KEY_PATH)
          read_age_public_key
        else
          Config.ensure_dirs
          private_bytes, public_bytes = Age::X25519.generate_keypair
          secret_key_str = Age::Bech32.encode("age-secret-key-", private_bytes).upcase
          public_key_str = Age::Bech32.encode("age", public_bytes)

          File.write(Config::AGE_KEY_PATH, "# created by dirless-connect\n#{secret_key_str}\n")
          File.chmod(Config::AGE_KEY_PATH, 0o600)
          public_key_str
        end
      end

      # Generates the SSH Ed25519 keypair if it doesn't exist yet.
      # Returns the public key string (ssh-ed25519 ...).
      def self.ensure_ssh_key : String
        if File.exists?(Config::SSH_KEY_PATH)
          File.read(Config::SSH_PUB_PATH).strip
        else
          Config.ensure_dirs
          status = Process.run(
            "ssh-keygen",
            args: ["-t", "ed25519", "-f", Config::SSH_KEY_PATH, "-N", "", "-C", "dirless-connect"],
            output: Process::Redirect::Close,
            error: Process::Redirect::Close,
          )
          raise "ssh-keygen failed" unless status.success?
          File.read(Config::SSH_PUB_PATH).strip
        end
      end

      def self.age_public_key : String
        read_age_public_key
      end

      def self.age_secret_key : Age::SecretKey
        content = File.read(Config::AGE_KEY_PATH)
        key_line = content.lines.find { |l| l.starts_with?("AGE-SECRET-KEY-") }
        raise "Age identity file missing key line: #{Config::AGE_KEY_PATH}" unless key_line
        Age::SecretKey.new(key_line.strip)
      end

      def self.ssh_public_key : String
        File.read(Config::SSH_PUB_PATH).strip
      end

      private def self.read_age_public_key : String
        content = File.read(Config::AGE_KEY_PATH)
        key_line = content.lines.find { |l| l.starts_with?("AGE-SECRET-KEY-") }
        raise "Age identity file missing key line: #{Config::AGE_KEY_PATH}" unless key_line
        secret_key_str = key_line.strip
        _, private_bytes = Age::Bech32.decode(secret_key_str)
        public_bytes = Age::X25519.public_from_private(private_bytes)
        Age::Bech32.encode("age", public_bytes)
      end
    end
  end
end
