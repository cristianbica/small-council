class CouncilAdvisor < ApplicationRecord
  # No acts_as_tenant needed - join table, scoped through council/advisor
  belongs_to :council
  belongs_to :advisor

  validates :council, presence: true
  validates :advisor, presence: true
  validates :advisor_id, uniqueness: { scope: :council_id }
  validates :position, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
end
