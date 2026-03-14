# frozen_string_literal: true

require "test_helper"

module SourceMonitor
  module Security
    class ParameterSanitizerTest < ActiveSupport::TestCase
      test "safe_redirect_path returns path when input starts with /" do
        assert_equal "/source_monitor/sources", ParameterSanitizer.safe_redirect_path("/source_monitor/sources")
      end

      test "safe_redirect_path returns nil when input is blank" do
        assert_nil ParameterSanitizer.safe_redirect_path("")
        assert_nil ParameterSanitizer.safe_redirect_path(nil)
      end

      test "safe_redirect_path returns nil when input is a full URL" do
        assert_nil ParameterSanitizer.safe_redirect_path("https://evil.com/steal")
        assert_nil ParameterSanitizer.safe_redirect_path("http://evil.com")
      end

      test "safe_redirect_path returns nil for XSS injection attempts" do
        assert_nil ParameterSanitizer.safe_redirect_path("javascript:alert(1)")
        assert_nil ParameterSanitizer.safe_redirect_path("<script>alert(1)</script>")
      end

      test "safe_redirect_path sanitizes input before checking" do
        result = ParameterSanitizer.safe_redirect_path("/sources<script>alert(1)</script>")
        assert_equal "/sourcesalert(1)", result
      end
    end
  end
end
