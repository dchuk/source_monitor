# frozen_string_literal: true

require "openssl"
require "net/http"
require "socket"

module SourceMonitor
  module HTTP
    module AIAResolver
      CONNECT_TIMEOUT = 5
      DOWNLOAD_TIMEOUT = 5
      CACHE_TTL = 3600 # 1 hour

      class << self
        def resolve(hostname, port: 443)
          cached = cache_lookup(hostname)
          return cached if cached

          cert = fetch_leaf_certificate(hostname, port)
          return unless cert

          url = extract_aia_url(cert)
          return unless url

          intermediate = download_certificate(url)
          return unless intermediate

          cache_store(hostname, intermediate)
          intermediate
        rescue StandardError
          nil
        end

        def enhanced_cert_store(additional_certs)
          store = OpenSSL::X509::Store.new
          store.set_default_paths

          Array(additional_certs).each do |cert|
            store.add_cert(cert)
          rescue OpenSSL::X509::StoreError
            # Already in store or invalid -- skip
          end

          store
        end

        def clear_cache!
          @mutex.synchronize { @cache.clear }
        end

        def cache_size
          @mutex.synchronize { @cache.size }
        end

        private

        def cache_lookup(hostname)
          @mutex.synchronize do
            entry = @cache[hostname]
            return unless entry
            return entry[:cert] if entry[:expires_at] > Time.now

            @cache.delete(hostname)
            nil
          end
        end

        def cache_store(hostname, cert)
          @mutex.synchronize do
            @cache[hostname] = { cert: cert, expires_at: Time.now + CACHE_TTL }
          end
        end

        def fetch_leaf_certificate(hostname, port)
          tcp = Socket.tcp(hostname, port, connect_timeout: CONNECT_TIMEOUT)
          ssl_context = OpenSSL::SSL::SSLContext.new
          ssl_context.verify_mode = OpenSSL::SSL::VERIFY_NONE

          ssl = OpenSSL::SSL::SSLSocket.new(tcp, ssl_context)
          ssl.hostname = hostname
          ssl.connect

          ssl.peer_cert
        rescue StandardError
          nil
        ensure
          ssl&.close rescue nil # rubocop:disable Style/RescueModifier
          tcp&.close rescue nil # rubocop:disable Style/RescueModifier
        end

        def extract_aia_url(cert)
          return unless cert.respond_to?(:ca_issuer_uris)

          uris = cert.ca_issuer_uris
          return if uris.nil? || uris.empty?

          uris.first.to_s
        rescue StandardError
          nil
        end

        def download_certificate(url)
          uri = URI.parse(url)
          http = Net::HTTP.new(uri.host, uri.port)
          http.open_timeout = DOWNLOAD_TIMEOUT
          http.read_timeout = DOWNLOAD_TIMEOUT

          response = http.get(uri.request_uri)
          return unless response.is_a?(Net::HTTPSuccess)

          body = response.body
          parse_certificate(body)
        rescue StandardError
          nil
        end

        def parse_certificate(body)
          OpenSSL::X509::Certificate.new(body) # tries DER first, then PEM
        rescue OpenSSL::X509::CertificateError
          nil
        end
      end

      @mutex = Mutex.new
      @cache = {}
    end
  end
end
