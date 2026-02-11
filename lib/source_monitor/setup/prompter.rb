# frozen_string_literal: true

require "thor"

module SourceMonitor
  module Setup
    class Prompter
      def initialize(shell: Thor::Shell::Basic.new, auto_yes: false)
        @shell = shell
        @auto_yes = auto_yes
      end

      def ask(question, default: nil)
        return default if auto_yes

        prompt = default ? "#{question} [#{default}]" : question
        response = shell.ask(prompt).to_s.strip
        response.empty? ? default : response
      end

      def yes?(question, default: true)
        return default if auto_yes

        suffix = default ? "Y/n" : "y/N"
        response = shell.ask("#{question} (#{suffix})").to_s.strip.downcase
        return default if response.empty?

        %w[y yes].include?(response)
      end

      private

      attr_reader :shell, :auto_yes
    end
  end
end
