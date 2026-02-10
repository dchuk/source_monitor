# frozen_string_literal: true

require "bundler"
require "digest"
require "fileutils"
require "open3"
require "rails/generators"
require "rails/generators/rails/app/app_generator"

module HostAppHarness
  extend self

  ENGINE_ROOT = File.expand_path("../..", __dir__)
  TMP_ROOT = File.expand_path("../tmp", __dir__)
  TARGET_RUBY_VERSION = File.read(File.expand_path("../../.ruby-version", __dir__)).strip
  BUNDLE_ROOT = File.join(ENGINE_ROOT, "tmp", "bundles", RUBY_VERSION)
  LEGACY_BUNDLE_ROOT = File.join(TMP_ROOT, "bundles")

  FileUtils.rm_rf(LEGACY_BUNDLE_ROOT) if Dir.exist?(LEGACY_BUNDLE_ROOT)

  TEMPLATE_OPTIONS = {
    default: [
      "--skip-test",
      "--skip-system-test",
      "--skip-hotwire",
      "--skip-javascript",
      "--skip-css",
      "--skip-action-mailer",
      "--skip-action-mailbox",
      "--skip-action-text",
      "--skip-active-storage",
      "--skip-git",
      "--skip-kamal",
      "--skip-docker",
      "--skip-bundle"
    ],
    api: [
      "--api",
      "--skip-test",
      "--skip-system-test",
      "--skip-hotwire",
      "--skip-javascript",
      "--skip-css",
      "--skip-action-mailer",
      "--skip-action-mailbox",
      "--skip-action-text",
      "--skip-active-storage",
      "--skip-git",
      "--skip-kamal",
      "--skip-docker",
      "--skip-bundle"
    ]
  }.freeze

  def prepare_working_directory(template: :default)
    ensure_ruby_version!
    capture_override_from_env!
    ensure_template!(template)
    reset_working_directory!(template)
    @current_template = template
    yield current_work_root if block_given?
    ensure_bundle_installed!(current_work_root)
  end

  def cleanup_working_directory
    return unless @current_template

    FileUtils.rm_rf(current_work_root)
    @current_template = nil
  end

  def bundle_exec!(*command, env: {})
    with_working_directory(env:) do |resolved_env|
      bundle_command = rbenv_available? ? [ "rbenv", "exec", "bundle", "exec", *command ] : [ "bundle", "exec", *command ]
      output, status = Open3.capture2e(resolved_env, *bundle_command)
      raise_command_failure(command, output) unless status.success?
      output
    end
  end

  def exist?(relative_path)
    File.exist?(File.join(current_work_root, relative_path))
  end

  def read(relative_path)
    File.read(File.join(current_work_root, relative_path))
  end

  def digest_files(relative_paths)
    relative_paths.index_with { |path| digest(path) }
  end

  def digest(relative_path)
    Digest::SHA256.hexdigest(read(relative_path))
  end

  private

  def current_work_root
    raise "call prepare_working_directory before interacting with HostAppHarness" unless @current_template

    work_root(@current_template)
  end

  def ensure_template!(template)
    ensure_rails_available!
    root = template_root(template)
    if File.exist?(File.join(root, "Gemfile.lock"))
      if template_ruby_version_current?(root)
        ensure_queue_config!(root)
        ensure_sqlite_json_patch!(root)
        return
      end
      FileUtils.rm_rf(root)
    end

    FileUtils.rm_rf(root)
    generate_host_app_template!(template)
    pin_ruby_version!(root)
    append_engine_to_gemfile!(root)
    ensure_queue_config!(root)
    ensure_sqlite_json_patch!(root)
    ensure_bundle_installed!(root)
  end

  def reset_working_directory!(template)
    FileUtils.rm_rf(work_root(template))
    FileUtils.mkdir_p(File.dirname(work_root(template)))
    FileUtils.cp_r("#{template_root(template)}/.", work_root(template))
    ensure_queue_config!(work_root(template))
    ensure_sqlite_json_patch!(work_root(template))
  end

  def generate_host_app_template!(template)
    args = [ template_root(template), *TEMPLATE_OPTIONS.fetch(template) ]

    Bundler.with_unbundled_env do
      SourceMonitor::Engine.eager_load!
      Rails::Generators::AppGenerator.start(args, behavior: :invoke)
    end
  end

  def append_engine_to_gemfile!(root)
    gemfile = File.join(root, "Gemfile")
    gem_path = override_gem_path || ENGINE_ROOT
    File.open(gemfile, "a") do |file|
      file.puts
      file.puts %(gem "source_monitor", path: "#{gem_path}")
    end
  end

  def ensure_bundle_installed!(root)
    Bundler.with_unbundled_env do
      env = default_env(root)
      FileUtils.mkdir_p(env.fetch("BUNDLE_PATH"))
      next if bundle_satisfied?(env, chdir: root)

      run_bundler!(env, %w[install --jobs 4 --retry 3 --quiet], chdir: root)
    end
  end

  def bundle_satisfied?(env, chdir: current_work_root)
    bundle_command = rbenv_available? ? [ "rbenv", "exec", "bundle", "check" ] : [ "bundle", "check" ]
    system(env, *bundle_command, chdir: chdir, out: File::NULL, err: File::NULL)
  end

  def with_working_directory(env: {})
    Bundler.with_unbundled_env do
      Dir.chdir(current_work_root) do
        merged_env = default_env.merge(env)
        yield merged_env
      end
    end
  end

  def run_bundler!(env, args, chdir: current_work_root)
    bundle_command = rbenv_available? ? [ "rbenv", "exec", "bundle", *args ] : [ "bundle", *args ]
    output, status = Open3.capture2e(env, *bundle_command, chdir: chdir)
    raise_command_failure([ "bundle", *args ], output) unless status.success?
  end

  def rbenv_available?
    @rbenv_available ||= system("which rbenv > /dev/null 2>&1")
  end

  def default_env(root = current_work_root)
    env = {
      "BUNDLE_GEMFILE" => File.join(root, "Gemfile"),
      "BUNDLE_IGNORE_CONFIG" => "1",
      "BUNDLE_PATH" => BUNDLE_ROOT,
      "BUNDLE_CACHE_ALL" => "1"
    }
    env["POSTGRES_HOST"] ||= ENV.fetch("POSTGRES_HOST", "localhost")
    env["POSTGRES_USER"] ||= ENV.fetch("POSTGRES_USER", "postgres")
    env["POSTGRES_PASSWORD"] ||= ENV.fetch("POSTGRES_PASSWORD", "")
    env["POSTGRES_DB"] ||= ENV.fetch("POSTGRES_DB", "sourcemon_dummy_development")
    env["POSTGRES_TEST_DB"] ||= ENV.fetch("POSTGRES_TEST_DB", "sourcemon_dummy_test")
    env["RBENV_VERSION"] = TARGET_RUBY_VERSION if rbenv_available?
    env
  end

  def raise_command_failure(command, output)
    message = [
      "HostAppHarness command failed: #{Array(command).join(" ")}",
      output
    ].compact.join("\n")

    raise RuntimeError, message
  end

  def template_root(template)
    File.join(TMP_ROOT, "host_app_template_#{template}#{override_template_suffix}")
  end

  def work_root(template)
    File.join(TMP_ROOT, "host_app_#{template}#{override_template_suffix}#{worker_suffix}")
  end

  def worker_suffix
    value = ENV.fetch("TEST_ENV_NUMBER", "")
    return "" if value.empty?

    "_worker_#{value}"
  end

  def pin_ruby_version!(root)
    version = desired_host_ruby_version
    File.write(File.join(root, ".ruby-version"), "#{version}\n")
    gemfile = File.join(root, "Gemfile")
    contents = File.read(gemfile)
    replacement = %(ruby "#{version}")
    if contents.match?(/^ruby /)
      contents.sub!(/^ruby .+$/, replacement)
    else
      contents = "#{replacement}\n#{contents}"
    end
    File.write(gemfile, contents)
  end

  def override_template_suffix
    path = override_gem_path
    return "" unless path

    digest = Digest::SHA256.hexdigest(path)[0, 8]
    "_override_#{digest}"
  end

  def override_gem_path
    @override_gem_path
  end

  def capture_override_from_env!
    raw = ENV["SOURCE_MONITOR_GEM_PATH"]
    return @override_gem_path = nil if raw.nil?

    value = raw.strip
    return @override_gem_path = nil if value.empty?

    @override_gem_path = File.expand_path(value)
  end

  def ensure_ruby_version!
    return if ::RUBY_VERSION.start_with?(TARGET_RUBY_VERSION)

    if rbenv_available?
      raise <<~MESSAGE
        SourceMonitor requires Ruby #{TARGET_RUBY_VERSION}. Detected #{::RUBY_VERSION}.
        Please install #{TARGET_RUBY_VERSION} (e.g., via rbenv: `rbenv install #{TARGET_RUBY_VERSION}`) and re-run the test suite.
      MESSAGE
    else
      Kernel.warn <<~MESSAGE
        SourceMonitor expected Ruby #{TARGET_RUBY_VERSION} but detected #{::RUBY_VERSION}.
        Proceeding with #{::RUBY_VERSION} because rbenv is not available; ensure CI installs Ruby #{TARGET_RUBY_VERSION} for full parity.
      MESSAGE
    end
  end

  def ensure_rails_available!
    Gem::Specification.find_by_name("rails", ">= 8.0.3")
  rescue Gem::LoadError
    raise <<~MESSAGE
      SourceMonitor's host app harness expects Rails >= 8.0.3 to be installed.
      Run `bundle install` in the engine directory to install Rails before executing the test suite.
    MESSAGE
  end

  def template_ruby_version_current?(root)
    cached = File.read(File.join(root, ".ruby-version")).strip
    cached == TARGET_RUBY_VERSION
  rescue Errno::ENOENT
    false
  end

  def desired_host_ruby_version
    return TARGET_RUBY_VERSION if ::RUBY_VERSION.start_with?(TARGET_RUBY_VERSION)
    return TARGET_RUBY_VERSION if rbenv_available?

    ::RUBY_VERSION
  end

  def ensure_queue_config!(root)
    path = File.join(root, "config", "queue.yml")
    return if File.exist?(path)

    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, <<~YAML)
      development:
        queues:
          default:
            concurrency: 1

      test:
        queues:
          default:
            concurrency: 1

      production:
        queues:
          default:
            concurrency: 5
    YAML
  end

  def ensure_sqlite_json_patch!(root)
    initializer_path = File.join(root, "config", "initializers", "sqlite_jsonb_patch.rb")
    FileUtils.mkdir_p(File.dirname(initializer_path))
    File.write(initializer_path, <<~RUBY)
      # frozen_string_literal: true

      require "active_support"

      ActiveSupport.on_load(:active_record) do
        begin
          require "active_record/connection_adapters/sqlite3_adapter"
        rescue LoadError
          next
        end

        unless defined?(SourceMonitor::SQLiteJsonbShim)
          module SourceMonitor
            module SQLiteJsonbShim
              def jsonb(name, **options)
                json(name, **options)
              end
            end
          end
        end

        targets = []
        if defined?(ActiveRecord::ConnectionAdapters::SQLite3::TableDefinition)
          targets << ActiveRecord::ConnectionAdapters::SQLite3::TableDefinition
        elsif defined?(ActiveRecord::ConnectionAdapters::SQLite3Adapter::TableDefinition)
          targets << ActiveRecord::ConnectionAdapters::SQLite3Adapter::TableDefinition
        end

        if defined?(ActiveRecord::ConnectionAdapters::SQLite3::ColumnMethods)
          targets << ActiveRecord::ConnectionAdapters::SQLite3::ColumnMethods
        elsif defined?(ActiveRecord::ConnectionAdapters::SQLite3Adapter::ColumnMethods)
          targets << ActiveRecord::ConnectionAdapters::SQLite3Adapter::ColumnMethods
        end

        targets.each do |target|
          next if target < SourceMonitor::SQLiteJsonbShim

          target.prepend(SourceMonitor::SQLiteJsonbShim)
        end
      end
    RUBY
  end
end
