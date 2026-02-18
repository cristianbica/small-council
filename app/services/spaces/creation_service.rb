module Spaces
  class CreationService
    def self.create_default_for_account(account)
      account.spaces.create!(
        name: "General",
        description: "Default space for your councils"
      )
    end
  end
end
