class CouncilAdvisor < ApplicationRecord
  # acts_as_tenant :account will be enabled when gem is installed
  belongs_to :council
  belongs_to :advisor

  validates :council, presence: true
  validates :advisor, presence: true
  validates :advisor_id, uniqueness: { scope: :council_id }
  validates :position, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
end
