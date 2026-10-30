class MakeCustomerIdentityPhonePrimary < ActiveRecord::Migration[7.0]
  def up
    # Remove composite unique index (phone,email) so phone can be the single identity key.
    remove_index :customer_identities, name: "idx_customer_identities_phone_email" if index_name_exists?(:customer_identities, "idx_customer_identities_phone_email")

    # Normalize existing phone values to digits-only (best-effort).
    execute <<~SQL
      UPDATE customer_identities
      SET phone_normalized = regexp_replace(phone_normalized, '[^0-9]', '', 'g')
      WHERE phone_normalized IS NOT NULL;
    SQL

    # Dedupe rows with the same phone by keeping the lowest id.
    # First, repoint global_customer_stats to the kept identity id.
    execute <<~SQL
      UPDATE global_customer_stats g
      SET customer_identity_id = keep.id
      FROM customer_identities dup
      JOIN customer_identities keep
        ON keep.phone_normalized = dup.phone_normalized
       AND keep.id < dup.id
      WHERE g.customer_identity_id = dup.id
        AND dup.phone_normalized IS NOT NULL;
    SQL

    # Now delete the duplicate identities.
    # If any stats rows still point at duplicates (edge cases), remove them; they'll be recomputed on next ingest.
    execute <<~SQL
      DELETE FROM global_customer_stats g
      USING customer_identities dup, customer_identities keep
      WHERE g.customer_identity_id = dup.id
        AND dup.id > keep.id
        AND dup.phone_normalized IS NOT NULL
        AND dup.phone_normalized = keep.phone_normalized;
    SQL

    execute <<~SQL
      DELETE FROM customer_identities dup
      USING customer_identities keep
      WHERE dup.id > keep.id
        AND dup.phone_normalized IS NOT NULL
        AND dup.phone_normalized = keep.phone_normalized;
    SQL

    add_index :customer_identities, :phone_normalized, unique: true, where: "phone_normalized IS NOT NULL", name: "idx_customer_identities_phone_unique"
  end

  def down
    remove_index :customer_identities, name: "idx_customer_identities_phone_unique" if index_name_exists?(:customer_identities, "idx_customer_identities_phone_unique")
    add_index :customer_identities, [:phone_normalized, :email_normalized], unique: true, name: "idx_customer_identities_phone_email"
  end
end

