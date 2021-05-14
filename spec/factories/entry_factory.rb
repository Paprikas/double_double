FactoryBot.define do
  factory :entry, class: DoubleDouble::Entry do
    description { FactoryBot.generate(:entry_type_description) }
  end

  sequence :entry_description do |n|
    "entry description #{n}"
  end
end
