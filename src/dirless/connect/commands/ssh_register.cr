require "http/client"
require "json"
require "../config"
require "../keypairs"

module Dirless
  module Connect
    module Commands
      # dirless-connect ssh register
      #
      # One-time bootstrap: generates both keypairs and sends a magic-link request
      # to the Dirless ops API. The user clicks the link in their email; no polling.
      class SshRegister
        def run(args : Array(String)) : Int32
          customer_name, ops_url, _ = Config.load

          # Allow overrides via flags: --customer NAME --email EMAIL --username NAME --url URL
          i = 0
          email = ""
          username = ""
          while i < args.size
            case args[i]
            when "--customer"
              i += 1
              customer_name = args[i]? || ""
            when "--email"
              i += 1
              email = args[i]? || ""
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
            print "Customer name (from your Dirless portal): "
            customer_name = gets.to_s.strip
          end

          if email.empty?
            print "Your email address: "
            email = gets.to_s.strip.downcase
          end

          if username.empty?
            print "Your Linux username on enrolled hosts: "
            username = gets.to_s.strip.downcase
          end

          if customer_name.empty? || email.empty? || username.empty?
            STDERR.puts "Error: customer name, email, and username are required."
            return 1
          end

          STDOUT.puts "Generating keypairs…"
          age_public_key = Keypairs.ensure_age_key
          ssh_public_key = Keypairs.ensure_ssh_key

          # Persist customer name, ops URL, and username for future logins.
          Config.save(customer_name, ops_url, username)

          STDOUT.puts "Sending registration request to #{ops_url}…"

          begin
            response = HTTP::Client.post(
              "#{ops_url}/v1/portal/bootstrap/request",
              headers: HTTP::Headers{"Content-Type" => "application/json"},
              body: {
                "customer_name"  => customer_name,
                "email"          => email,
                "username"       => username,
                "age_public_key" => age_public_key,
                "ssh_public_key" => ssh_public_key,
              }.to_json,
            )

            case response.status_code
            when 200
              STDOUT.puts ""
              STDOUT.puts "Check your email (#{email}) for a registration link."
              STDOUT.puts "Click it to complete setup, then run:"
              STDOUT.puts ""
              STDOUT.puts "dirless-connect ssh login"
              STDOUT.puts ""
              0
            when 404
              STDERR.puts "Error: no Dirless account found for #{email} in customer #{customer_name}."
              STDERR.puts "Make sure the email matches your IAM Identity Center user or portal account."
              1
            when 422
              parsed = JSON.parse(response.body) rescue nil
              msg = parsed.try(&.["error"]?.try(&.as_s?)) || response.body
              STDERR.puts "Validation error: #{msg}"
              1
            else
              STDERR.puts "Unexpected response (HTTP #{response.status_code}): #{response.body}"
              1
            end
          rescue ex : IO::Error | Socket::Error | OpenSSL::SSL::Error
            STDERR.puts "Could not reach #{ops_url}: #{ex.message}"
            STDERR.puts "Check your network connection and try again."
            1
          end
        end
      end
    end
  end
end
