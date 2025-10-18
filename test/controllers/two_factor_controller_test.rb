require "test_helper"

class TwoFactorControllerTest < ActionDispatch::IntegrationTest
  test "should get new" do
    get two_factor_new_url
    assert_response :success
  end

  test "should get create" do
    get two_factor_create_url
    assert_response :success
  end
end
