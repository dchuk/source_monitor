# frozen_string_literal: true

module SourceMonitor
  module SetSource
    extend ActiveSupport::Concern

    private

    def set_source
      @source = Source.find(params[:source_id])
    end
  end
end
