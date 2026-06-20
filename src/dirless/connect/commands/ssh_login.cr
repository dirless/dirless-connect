require "http/client"
require "json"
require "base64"
require "age-crystal"
require "../config"
require "../keypairs"

module Dirless
  module Connect
    module Commands
      # dirless-connect ssh login
      #
      # Obtains a short-lived SSH certificate. Flow:
      #   1. Check if existing cert is still valid (>1 hour remaining → skip).
      #   2. POST /v1/portal/cert/challenge → receive nonce encrypted to our age key.
      #   3. Decrypt nonce with local age private key.
      #   4. POST /v1/portal/cert/sign with plaintext nonce → receive SSH certificate.
      #   5. Write cert to ~/.config/dirless-connect/ssh/id_ed25519-cert.pub.
      #   6. Ensure ~/.ssh/config includes the IdentityFile stanza.
      class SshLogin
        SKIP_REISSUE_THRESHOLD = 1.hour

        def run(args : Array(String)) : Int32
          customer_name, ops_url, username = Config.load
          i = 0
          while i < args.size
            case args[i]
            when "--customer"
              i += 1
              customer_name = args[i]? || ""
            when "--username"
              i += 1
              username = args[i]? || ""
            when "--url", "--ops-url"
              i += 1
              ops_url = args[i]? || ops_url
            end
            i += 1
          end

          if customer_name.empty?
            print "Customer name: "
            customer_name = gets.to_s.strip
          end

          if customer_name.empty?
            STDERR.puts "Error: customer name required. Run 'dirless-connect ssh register' first."
            return 1
          end

          unless File.exists?(Config::AGE_KEY_PATH)
            STDERR.puts "No keypair found. Run 'dirless-connect ssh register' first."
            return 1
          end

          # Check existing cert validity to avoid unnecessary round-trips.
          if (remaining = cert_remaining_seconds) && remaining > SKIP_REISSUE_THRESHOLD.total_seconds
            hours = (remaining / 3600).round(1)
            STDOUT.puts "Certificate is still valid for #{hours} hours. Nothing to do."
            return 0
          end

          if username.empty?
            # Try to derive from the cert comment if one exists.
            username = read_cert_username || ""
          end

          if username.empty?
            print "Your Dirless username: "
            username = gets.to_s.strip
          end

          if username.empty?
            STDERR.puts "Error: username required."
            return 1
          end

          STDOUT.puts "Requesting challenge…"

          # Step 1: request a challenge
          challenge_resp = begin
            HTTP::Client.post(
              "#{ops_url}/v1/portal/cert/challenge",
              headers: HTTP::Headers{"Content-Type" => "application/json"},
              body: {"customer_name" => customer_name, "username" => username}.to_json,
            )
          rescue ex : IO::Error | Socket::Error | OpenSSL::SSL::Error
            STDERR.puts "Could not reach #{ops_url}: #{ex.message}"
            return 1
          end

          unless challenge_resp.status_code == 200
            parsed = JSON.parse(challenge_resp.body) rescue nil
            msg = parsed.try(&.["error"]?.try(&.as_s?)) || challenge_resp.body
            STDERR.puts "Challenge failed (HTTP #{challenge_resp.status_code}): #{msg}"
            if challenge_resp.status_code == 404
              STDERR.puts "Have you completed registration? Run 'dirless-connect ssh register' first."
            end
            return 1
          end

          nonce_encrypted_b64 = begin
            JSON.parse(challenge_resp.body)["nonce_encrypted"].as_s
          rescue ex
            STDERR.puts "Unexpected challenge response: #{challenge_resp.body}"
            return 1
          end

          # Step 2: decrypt the nonce
          nonce_plaintext = begin
            ciphertext = Base64.decode(nonce_encrypted_b64)
            secret_key = Keypairs.age_secret_key
            String.new(Age.decrypt(ciphertext, secret_key))
          rescue ex
            STDERR.puts "Failed to decrypt challenge: #{ex.message}"
            STDERR.puts "Your age key may not match the registered key. Run 'dirless-connect ssh register' to re-register."
            return 1
          end

          STDOUT.puts "Signing certificate…"

          # Step 3: submit nonce to get certificate
          sign_resp = begin
            HTTP::Client.post(
              "#{ops_url}/v1/portal/cert/sign",
              headers: HTTP::Headers{"Content-Type" => "application/json"},
              body: {
                "customer_name" => customer_name,
                "username"      => username,
                "nonce"         => nonce_plaintext,
              }.to_json,
            )
          rescue ex : IO::Error | Socket::Error | OpenSSL::SSL::Error
            STDERR.puts "Could not reach #{ops_url}: #{ex.message}"
            return 1
          end

          unless sign_resp.status_code == 200
            parsed = JSON.parse(sign_resp.body) rescue nil
            msg = parsed.try(&.["error"]?.try(&.as_s?)) || sign_resp.body
            STDERR.puts "Signing failed (HTTP #{sign_resp.status_code}): #{msg}"
            return 1
          end

          parsed_sign = begin
            JSON.parse(sign_resp.body)
          rescue ex
            STDERR.puts "Unexpected sign response: #{sign_resp.body}"
            return 1
          end

          certificate  = parsed_sign["certificate"].as_s
          valid_before = parsed_sign["valid_before"]?.try(&.as_s?) || "unknown"
          ttl_seconds  = parsed_sign["ttl_seconds"]?.try(&.as_i64?) || 0_i64

          # Step 4: write the certificate
          Config.ensure_dirs
          File.write(Config::SSH_CERT_PATH, certificate)
          File.chmod(Config::SSH_CERT_PATH, 0o600)

          hours = (ttl_seconds / 3600.0).round(1)
          STDOUT.puts ""
          STDOUT.puts "Certificate issued. Valid for #{hours} hours (until #{valid_before})."
          STDOUT.puts ""
          STDOUT.puts "To use it, add this to your ~/.ssh/config:"
          STDOUT.puts "  Host *"
          STDOUT.puts "    IdentityFile #{Config::SSH_KEY_PATH}"
          STDOUT.puts "    CertificateFile #{Config::SSH_CERT_PATH}"
          STDOUT.puts ""
          STDOUT.puts "Then SSH into any enrolled host:"
          STDOUT.puts "  ssh #{username}@<hostname>"
          STDOUT.puts ""
          0
        end

        private def cert_remaining_seconds : Float64?
          return nil unless File.exists?(Config::SSH_CERT_PATH)
          output = IO::Memory.new
          status = Process.run(
            "ssh-keygen", args: ["-L", "-f", Config::SSH_CERT_PATH],
            output: output, error: Process::Redirect::Close
          )
          return nil unless status.success?
          text = output.to_s
          # Parse "Valid: from ... to YYYY-MM-DDTHH:MM:SS"
          if m = text.match(/Valid:.*to (\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2})/)
            begin
              expiry = Time.parse_iso8601(m[1])
              diff = (expiry - Time.utc).total_seconds
              diff > 0 ? diff : nil
            rescue
              nil
            end
          end
        end

        private def read_cert_username : String?
          return nil unless File.exists?(Config::SSH_CERT_PATH)
          output = IO::Memory.new
          status = Process.run(
            "ssh-keygen", args: ["-L", "-f", Config::SSH_CERT_PATH],
            output: output, error: Process::Redirect::Close
          )
          return nil unless status.success?
          text = output.to_s
          # "Principals: username"
          if m = text.match(/Principals:\s+(\S+)/)
            m[1]
          end
        end

      end
    end
  end
end
