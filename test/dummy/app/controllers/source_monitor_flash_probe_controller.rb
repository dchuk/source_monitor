# frozen_string_literal: true

# Test-only controller exercising SourceMonitor::ApplicationController's
# response-local flash delivery for turbo_stream requests (issue #130).
#
# No real engine action triggers this path: engine turbo_stream actions emit
# toasts via TurboStreams::StreamResponder#toast (response-local) rather than
# setting a Rails flash. This probe sets a Rails flash and renders a
# non-redirect turbo_stream response so the +append_flash_toasts_to_turbo_stream+
# after_action runs and appends the toast to the response body.
class SourceMonitorFlashProbeController < SourceMonitor::ApplicationController
  def show
    flash[:notice] = "Saved via turbo stream"
    render turbo_stream: turbo_stream.append("probe", "ok")
  end
end
