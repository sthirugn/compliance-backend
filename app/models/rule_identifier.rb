# frozen_string_literal: true

# Stores the identifier for a rule
class RuleIdentifier < ApplicationRecord
  belongs_to :rule

  validates :label, presence: true
  validates :system, presence: true

  def self.from_openscap_parser(op_rule_identifier, rule_id)
    if op_rule_identifier.label # rubocop:disable Style/GuardClause
      find_or_initialize_by(label: op_rule_identifier.label,
                            system: op_rule_identifier.system,
                            rule_id: rule_id)
    end
  end
end
