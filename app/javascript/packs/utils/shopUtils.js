/**
 * Utility functions for shop-related operations
 */

/**
 * Checks if a shop has no valid charge ID (no subscription)
 * @param {Object} shop - The shop object
 * @returns {boolean} - true if shop has no charge ID, false otherwise
 */
export const hasNoChargeId = (shop) => {
  return !shop?.charge_id || shop.charge_id === null || shop.charge_id === "";
};

/**
 * Checks if a shop has a valid charge ID (has subscription)
 * @param {Object} shop - The shop object
 * @returns {boolean} - true if shop has a valid charge ID, false otherwise
 */
export const hasValidChargeId = (shop) => {
  return !hasNoChargeId(shop);
};
