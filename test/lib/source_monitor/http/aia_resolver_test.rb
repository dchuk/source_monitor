# frozen_string_literal: true

require "test_helper"

module SourceMonitor
  class HTTP::AIAResolverTest < ActiveSupport::TestCase
    teardown do
      SourceMonitor::HTTP::AIAResolver.clear_cache!
    end

    test "extract_aia_url returns URL for cert with AIA extension" do
      cert = build_cert_with_aia("http://example.com/ca.crt")
      url = SourceMonitor::HTTP::AIAResolver.send(:extract_aia_url, cert)

      assert_equal "http://example.com/ca.crt", url
    end

    test "extract_aia_url returns nil for cert without AIA" do
      cert = build_basic_cert
      url = SourceMonitor::HTTP::AIAResolver.send(:extract_aia_url, cert)

      assert_nil url
    end

    test "download_certificate parses DER body" do
      cert = build_basic_cert
      der_body = cert.to_der

      stub_request(:get, "http://example.com/intermediate.crt")
        .to_return(status: 200, body: der_body, headers: { "Content-Type" => "application/pkix-cert" })

      result = SourceMonitor::HTTP::AIAResolver.send(:download_certificate, "http://example.com/intermediate.crt")

      assert_instance_of OpenSSL::X509::Certificate, result
      assert_equal cert.subject.to_s, result.subject.to_s
    end

    test "download_certificate returns nil on HTTP 404" do
      stub_request(:get, "http://example.com/missing.crt")
        .to_return(status: 404, body: "Not Found")

      result = SourceMonitor::HTTP::AIAResolver.send(:download_certificate, "http://example.com/missing.crt")

      assert_nil result
    end

    test "download_certificate returns nil on timeout" do
      stub_request(:get, "http://example.com/slow.crt")
        .to_timeout

      result = SourceMonitor::HTTP::AIAResolver.send(:download_certificate, "http://example.com/slow.crt")

      assert_nil result
    end

    test "enhanced_cert_store returns store with default paths and added certs" do
      cert = build_basic_cert
      store = SourceMonitor::HTTP::AIAResolver.enhanced_cert_store([ cert ])

      assert_instance_of OpenSSL::X509::Store, store
    end

    test "enhanced_cert_store handles empty array" do
      store = SourceMonitor::HTTP::AIAResolver.enhanced_cert_store([])

      assert_instance_of OpenSSL::X509::Store, store
    end

    test "resolve caches result by hostname" do
      cert = build_basic_cert
      intermediate = build_basic_cert(cn: "Intermediate CA")

      call_count = 0
      SourceMonitor::HTTP::AIAResolver.stub(:fetch_leaf_certificate, ->(_h, _p) {
        call_count += 1
        cert
      }) do
        SourceMonitor::HTTP::AIAResolver.stub(:extract_aia_url, "http://example.com/ca.crt") do
          SourceMonitor::HTTP::AIAResolver.stub(:download_certificate, intermediate) do
            result1 = SourceMonitor::HTTP::AIAResolver.resolve("example.com")
            result2 = SourceMonitor::HTTP::AIAResolver.resolve("example.com")

            assert_equal 1, call_count
            assert_instance_of OpenSSL::X509::Certificate, result1
            assert_equal result1.to_der, result2.to_der
          end
        end
      end
    end

    test "resolve re-fetches after TTL expiration" do
      cert = build_basic_cert
      intermediate = build_basic_cert(cn: "Intermediate CA")

      call_count = 0
      SourceMonitor::HTTP::AIAResolver.stub(:fetch_leaf_certificate, ->(_h, _p) {
        call_count += 1
        cert
      }) do
        SourceMonitor::HTTP::AIAResolver.stub(:extract_aia_url, "http://example.com/ca.crt") do
          SourceMonitor::HTTP::AIAResolver.stub(:download_certificate, intermediate) do
            SourceMonitor::HTTP::AIAResolver.resolve("example.com")
            assert_equal 1, call_count

            travel(SourceMonitor::HTTP::AIAResolver::CACHE_TTL + 1) do
              SourceMonitor::HTTP::AIAResolver.resolve("example.com")
              assert_equal 2, call_count
            end
          end
        end
      end
    end

    test "clear_cache empties the cache" do
      cert = build_basic_cert
      intermediate = build_basic_cert(cn: "Intermediate CA")

      SourceMonitor::HTTP::AIAResolver.stub(:fetch_leaf_certificate, ->(_h, _p) { cert }) do
        SourceMonitor::HTTP::AIAResolver.stub(:extract_aia_url, "http://example.com/ca.crt") do
          SourceMonitor::HTTP::AIAResolver.stub(:download_certificate, intermediate) do
            SourceMonitor::HTTP::AIAResolver.resolve("example.com")
            assert_equal 1, SourceMonitor::HTTP::AIAResolver.cache_size

            SourceMonitor::HTTP::AIAResolver.clear_cache!
            assert_equal 0, SourceMonitor::HTTP::AIAResolver.cache_size
          end
        end
      end
    end

    test "resolve returns nil when hostname unreachable" do
      SourceMonitor::HTTP::AIAResolver.stub(:fetch_leaf_certificate, ->(_h, _p) { raise SocketError, "unreachable" }) do
        result = SourceMonitor::HTTP::AIAResolver.resolve("unreachable.example.com")

        assert_nil result
      end
    end

    private

    def build_basic_cert(cn: "Test Subject")
      key = OpenSSL::PKey::RSA.generate(2048)
      cert = OpenSSL::X509::Certificate.new
      cert.version = 2
      cert.serial = 1
      cert.subject = OpenSSL::X509::Name.parse("/CN=#{cn}")
      cert.issuer = cert.subject
      cert.public_key = key.public_key
      cert.not_before = Time.now - 3600
      cert.not_after = Time.now + 3600
      cert.sign(key, OpenSSL::Digest.new("SHA256"))
      cert
    end

    def build_cert_with_aia(aia_url)
      key = OpenSSL::PKey::RSA.generate(2048)
      cert = OpenSSL::X509::Certificate.new
      cert.version = 2
      cert.serial = 1
      cert.subject = OpenSSL::X509::Name.parse("/CN=AIA Test")
      cert.issuer = cert.subject
      cert.public_key = key.public_key
      cert.not_before = Time.now - 3600
      cert.not_after = Time.now + 3600

      ef = OpenSSL::X509::ExtensionFactory.new
      ef.subject_certificate = cert
      ef.issuer_certificate = cert
      cert.add_extension(ef.create_extension("authorityInfoAccess", "caIssuers;URI:#{aia_url}"))

      cert.sign(key, OpenSSL::Digest.new("SHA256"))
      cert
    end
  end
end
