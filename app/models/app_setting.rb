class AppSetting < ApplicationRecord
  validates :key, presence: true, uniqueness: true

  def self.get(key, default = nil)
    find_by(key: key)&.value.presence || default
  end

  def self.set(key, value)
    rec = find_or_initialize_by(key: key)
    rec.value = value
    rec.save!
    rec.value
  end
end
