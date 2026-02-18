# This file should ensure the existence of records required to run the application in every environment (production,
# development, test). The code here should be idempotent so that it can be executed at any point in every environment.

# Create demo account with user
demo_account = Account.find_or_create_by!(slug: "demo") do |account|
  account.name = "Demo Organization"
end

demo_user = demo_account.users.find_or_create_by!(email: "demo@example.com") do |user|
  user.password = "password123"
  user.role = :admin
end

puts "Created demo account: #{demo_account.name}"
puts "Demo user: #{demo_user.email} / password: password123"
