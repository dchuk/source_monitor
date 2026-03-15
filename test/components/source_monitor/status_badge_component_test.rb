# frozen_string_literal: true

require "test_helper"
require "view_component/test_helpers"
require "view_component/test_case"

module SourceMonitor
  class StatusBadgeComponentTest < ViewComponent::TestCase
    # -- Health statuses --

    test "renders working status with green classes" do
      render_inline(StatusBadgeComponent.new(status: "working"))

      assert_selector "span.bg-green-100.text-green-700", text: "Working"
      assert_no_selector "svg" # no spinner
    end

    test "renders declining status with yellow classes" do
      render_inline(StatusBadgeComponent.new(status: "declining"))

      assert_selector "span.bg-yellow-100.text-yellow-700", text: "Declining"
    end

    test "renders failing status with rose classes" do
      render_inline(StatusBadgeComponent.new(status: "failing"))

      assert_selector "span.bg-rose-100.text-rose-700", text: "Failing"
    end

    test "renders improving status with sky classes" do
      render_inline(StatusBadgeComponent.new(status: "improving"))

      assert_selector "span.bg-sky-100.text-sky-700", text: "Improving"
    end

    # -- Success / Failure --

    test "renders success status with green classes" do
      render_inline(StatusBadgeComponent.new(status: "success"))

      assert_selector "span.bg-green-100.text-green-700", text: "Success"
    end

    test "renders failed status with rose classes" do
      render_inline(StatusBadgeComponent.new(status: "failed"))

      assert_selector "span.bg-rose-100.text-rose-700", text: "Failed"
    end

    # -- Processing statuses with spinner --

    test "renders fetching status with spinner" do
      render_inline(StatusBadgeComponent.new(status: "fetching"))

      assert_selector "span.bg-blue-100.text-blue-700", text: "Processing"
      assert_selector "svg" # spinner present
    end

    test "renders processing status with spinner" do
      render_inline(StatusBadgeComponent.new(status: "processing"))

      assert_selector "span.bg-blue-100.text-blue-700"
      assert_selector "svg" # spinner present
    end

    test "suppresses spinner when show_spinner is false" do
      render_inline(StatusBadgeComponent.new(status: "fetching", show_spinner: false))

      assert_selector "span.bg-blue-100.text-blue-700", text: "Processing"
      assert_no_selector "svg"
    end

    # -- Pending / Queued --

    test "renders queued status with amber classes" do
      render_inline(StatusBadgeComponent.new(status: "queued"))

      assert_selector "span.bg-amber-100.text-amber-700", text: "Queued"
    end

    test "renders pending status with amber classes" do
      render_inline(StatusBadgeComponent.new(status: "pending"))

      assert_selector "span.bg-amber-100.text-amber-700", text: "Pending"
    end

    # -- Inactive statuses --

    test "renders idle status with slate classes" do
      render_inline(StatusBadgeComponent.new(status: "idle"))

      assert_selector "span.bg-slate-100.text-slate-600", text: "Idle"
    end

    test "renders disabled status with darker slate classes" do
      render_inline(StatusBadgeComponent.new(status: "disabled"))

      assert_selector "span.bg-slate-200.text-slate-600", text: "Disabled"
    end

    test "renders paused status with amber classes" do
      render_inline(StatusBadgeComponent.new(status: "paused"))

      assert_selector "span.bg-amber-100.text-amber-700", text: "Paused"
    end

    test "renders blocked status with rose classes" do
      render_inline(StatusBadgeComponent.new(status: "blocked"))

      assert_selector "span.bg-rose-100.text-rose-700", text: "Blocked"
    end

    # -- Unknown status fallback --

    test "renders unknown status with slate fallback classes" do
      render_inline(StatusBadgeComponent.new(status: "some_unknown_status"))

      assert_selector "span.bg-slate-100.text-slate-600", text: "Some unknown status"
    end

    # -- Label override --

    test "allows label override" do
      render_inline(StatusBadgeComponent.new(status: "success", label: "Completed"))

      assert_selector "span.bg-green-100", text: "Completed"
    end

    # -- Size variants --

    test "renders sm size" do
      render_inline(StatusBadgeComponent.new(status: "working", size: :sm))

      assert_selector "span.px-2.py-0\\.5"
    end

    test "renders md size by default" do
      render_inline(StatusBadgeComponent.new(status: "working"))

      assert_selector "span.px-3.py-1"
    end

    test "renders lg size" do
      render_inline(StatusBadgeComponent.new(status: "working", size: :lg))

      assert_selector "span.px-4"
    end

    # -- Symbol status --

    test "accepts symbol status" do
      render_inline(StatusBadgeComponent.new(status: :working))

      assert_selector "span.bg-green-100.text-green-700", text: "Working"
    end

    # -- Data attributes --

    test "includes data-status attribute" do
      render_inline(StatusBadgeComponent.new(status: "working"))

      assert_selector "span[data-status='working']"
    end

    test "includes custom data attributes" do
      render_inline(StatusBadgeComponent.new(status: "working", data: { testid: "custom-badge" }))

      assert_selector "span[data-testid='custom-badge']"
    end

    # -- Consistent badge markup --

    test "always includes rounded-full and font-semibold classes" do
      render_inline(StatusBadgeComponent.new(status: "working"))

      assert_selector "span.inline-flex.items-center.rounded-full.font-semibold"
    end
  end
end
