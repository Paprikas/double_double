module DoubleDouble
  # entries are the recording of debits and credits to various accounts.
  # This table can be thought of as a traditional accounting Journal.
  #
  # Posting to a Ledger can be considered to happen automatically, since
  # Accounts have the reverse 'has_many' relationship to either it's credit or
  # debit entries
  #
  # @example
  #   cash = DoubleDouble::Asset.named('Cash')
  #   accounts_receivable = DoubleDouble::Asset.named('Accounts Receivable')
  #
  #   debit_amount = DoubleDouble::DebitAmount.new(account: 'cash', amount: 1000)
  #   credit_amount = DoubleDouble::CreditAmount.new(account: 'accounts_receivable', amount: 1000)
  #
  #   entry = DoubleDouble::Entry.new(description: "Receiving payment on an invoice")
  #   entry.debit_amounts << debit_amount
  #   entry.credit_amounts << credit_amount
  #   entry.save
  #
  # @see http://en.wikipedia.org/wiki/Journal_entry Journal Entry
  #
  class Entry < ActiveRecord::Base
    self.table_name = "double_double_entries"

    belongs_to :entry_type
    belongs_to :initiator, polymorphic: true

    has_many :credit_amounts
    has_many :debit_amounts
    has_many :credit_accounts, through: :credit_amounts, source: :account
    has_many :debit_accounts, through: :debit_amounts, source: :account

    validates_presence_of :description
    validate :has_credit_amounts?
    validate :has_debit_amounts?
    validate :amounts_cancel?

    scope :by_entry_type, ->(et) { where(entry_type: et) }
    scope :by_initiator, ->(i) { where(initiator_id: i.id, initiator_type: i.class.base_class) }

    # Simple API for building a entry and associated debit and credit amounts
    #
    # @example
    #   entry = DoubleDouble::Entry.build(
    #     description: "Sold some widgets",
    #     debits: [
    #       {account: "Accounts Receivable", amount: 50, context: @some_active_record_object}],
    #     credits: [
    #       {account: "Sales Revenue",       amount: 45},
    #       {account: "Sales Tax Payable",   amount:  5}])
    #
    # @return [DoubleDouble::Entry] A Entry with built credit and debit objects ready for saving
    def self.build args
      args.merge!({credits: args[:debits], debits: args[:credits]}) if args[:reversed]
      Entry.new.tap do |entry|
        entry.description = args.fetch(:description, nil)
        entry.entry_type = args.fetch(:entry_type, nil)
        entry.initiator = args.fetch(:initiator, nil)

        add_amounts_to_entry(args[:debits], entry, true)
        add_amounts_to_entry(args[:credits], entry, false)
      end
    end

    def self.create! args
      build(args).save!
    end

    def entry_type
      entry_type_id.nil? ? UnassignedEntryType : EntryType.find(entry_type_id)
    end

    private

    # Validation

    def has_credit_amounts?
      errors.add(:base, "Entry must have at least one credit amount") if credit_amounts.blank?
    end

    def has_debit_amounts?
      errors.add(:base, "Entry must have at least one debit amount") if debit_amounts.blank?
    end

    def amounts_cancel?
      errors.add(:base, "The credit and debit amounts are not equal") if difference_of_amounts.cents != 0
    end

    def difference_of_amounts
      credit_amount_total = credit_amounts.map(&:amount).reduce(:+) || Money.new(0)
      debit_amount_total = debit_amounts.map(&:amount).reduce(:+) || Money.new(0)
      credit_amount_total - debit_amount_total
    end

    # Assist entry building

    def self.add_amounts_to_entry amounts, entry, add_to_debits = true
      return if amounts.nil?

      ledger_side, amount_class = ledger_side_and_Amount_class(add_to_debits)

      add_amount_to_entry = ->(new_amount) { entry.send(ledger_side) << new_amount }
      generate_amount_obj = -> { amount_class.new }

      amounts.each do |amt|
        amount_parameters = prepare_amount_parameters amt.merge({entry: entry})
        new_amount = generate_amount_obj.call
        new_amount.assign_attributes amount_parameters
        add_amount_to_entry.call new_amount
      end
    end

    def self.ledger_side_and_Amount_class is_debit
      if is_debit
        [:debit_amounts, DebitAmount]
      else
        [:credit_amounts, CreditAmount]
      end
    end

    def self.prepare_amount_parameters args
      {account: Account.named_or_numbered(args[:account]),
       entry: args[:entry],
       amount: args[:amount],
       accountee: args.fetch(:accountee, nil),
       context: args.fetch(:context, nil),
       subcontext: args.fetch(:subcontext, nil)}
    end
  end
end
