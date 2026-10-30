# frozen_string_literal: true

module CustomBranded
  # SUPERSEDED: the design moved from provisioning shops rows to a separate
  # custom_branded_clients table — see ClientProvisioner. This alias only
  # exists so the constant still resolves; safe to delete this file.
  ShopProvisioner = ClientProvisioner
end
