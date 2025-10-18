Rails.application.configure do
  config.content_security_policy do |policy|
    policy.default_src :self
    policy.script_src  :self
    policy.style_src   :self
    policy.font_src    :self, :data
    policy.img_src     :self, :https, :data, :blob
    policy.media_src   :self, :blob
    policy.connect_src :self
    policy.object_src  :none
  end
end
