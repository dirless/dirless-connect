require "toml"

module Dirless
  module Connect
    # Manages ~/.config/dirless-connect/ — the user's local state directory.
    # Contains age identity, SSH keypair, and server config.
    module Config
      CONFIG_DIR    = File.join(ENV.fetch("HOME", "~"), ".config", "dirless-connect")
      SSH_DIR       = File.join(CONFIG_DIR, "ssh")
      AGE_KEY_PATH  = File.join(CONFIG_DIR, "identity.age")
      SSH_KEY_PATH  = File.join(SSH_DIR, "id_ed25519")
      SSH_PUB_PATH  = File.join(SSH_DIR, "id_ed25519.pub")
      SSH_CERT_PATH = File.join(SSH_DIR, "id_ed25519-cert.pub")
      CONFIG_PATH   = File.join(CONFIG_DIR, "config.toml")

      def self.ensure_dirs : Nil
        Dir.mkdir_p(CONFIG_DIR)
        File.chmod(CONFIG_DIR, 0o700)
        Dir.mkdir_p(SSH_DIR)
        File.chmod(SSH_DIR, 0o700)
      end

      # Returns {customer_name, ops_url, username} from the config file, or defaults.
      def self.load : {String, String, String}
        if File.exists?(CONFIG_PATH)
          data = TOML.parse(File.read(CONFIG_PATH))
          customer_name = data["customer_name"]?.try(&.as_s?) || ""
          ops_url       = data["ops_url"]?.try(&.as_s?) || default_ops_url
          username      = data["username"]?.try(&.as_s?) || ""
          {customer_name, ops_url, username}
        else
          {"", default_ops_url, ""}
        end
      end

      def self.save(customer_name : String, ops_url : String, username : String) : Nil
        ensure_dirs
        File.open(CONFIG_PATH, "w", perm: 0o600) do |f|
          f.print("customer_name = ")
          f.print(toml_string(customer_name))
          f.print("\nops_url       = ")
          f.print(toml_string(ops_url))
          f.print("\nusername      = ")
          f.print(toml_string(username))
          f.print("\n")
        end
      end

      # Encode a string as a TOML basic string (double-quoted, with mandatory escapes).
      # Crystal's String#inspect emits \u{XXXX} which is not valid TOML.
      private def self.toml_string(s : String) : String
        buf = String::Builder.new(s.bytesize + 2)
        buf << '"'
        s.each_char do |c|
          case c
          when '"'  then buf << "\\\""
          when '\\' then buf << "\\\\"
          when '\b' then buf << "\\b"
          when '\f' then buf << "\\f"
          when '\n' then buf << "\\n"
          when '\r' then buf << "\\r"
          when '\t' then buf << "\\t"
          else
            cp = c.ord
            if cp < 0x20 || cp == 0x7f
              buf << "\\u"
              buf << cp.to_s(16).rjust(4, '0')
            else
              buf << c
            end
          end
        end
        buf << '"'
        buf.to_s
      end

      private def self.default_ops_url : String
        ENV.fetch("DIRLESS_OPS_URL", "https://admin.dirless.com")
      end
    end
  end
end
