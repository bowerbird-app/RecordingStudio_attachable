# frozen_string_literal: true

require "test_helper"
require "stringio"

class EnvironmentDoctorTest < Minitest::Test
  Check = RecordingStudioAttachable::EnvironmentDoctor::Check

  def test_passing_checks_return_success
    output = StringIO.new
    doctor = RecordingStudioAttachable::EnvironmentDoctor.new(io: output)
    checks = [Check.new(status: :pass, label: "Image transformation", detail: nil)]

    result = doctor.stub(:server_checks, checks) do
      doctor.stub(:client_checks, []) { doctor.call }
    end

    assert result.success?
    assert_equal "PASS Image transformation\n", output.string
  end

  def test_required_failure_returns_failure
    output = StringIO.new
    doctor = RecordingStudioAttachable::EnvironmentDoctor.new(io: output)
    checks = [Check.new(status: :fail, label: "Variant processor", detail: "vips unavailable")]

    result = doctor.stub(:server_checks, checks) do
      doctor.stub(:client_checks, []) { doctor.call }
    end

    assert_not result.success?
    assert_includes output.string, "FAIL Variant processor: vips unavailable"
  end

  def test_uninspectable_client_wiring_warns_without_failing
    output = StringIO.new
    doctor = RecordingStudioAttachable::EnvironmentDoctor.new(io: output)
    warnings = [Check.new(status: :warn, label: "JavaScript wiring", detail: "could not be inspected")]

    result = doctor.stub(:server_checks, []) do
      doctor.stub(:client_checks, warnings) { doctor.call }
    end

    assert result.success?
    assert_equal "WARN JavaScript wiring: could not be inspected\n", output.string
  end
end
