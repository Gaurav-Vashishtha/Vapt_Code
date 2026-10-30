/**
 * Plan feature entries may be plain strings or { text: string, bold?: boolean }.
 */
export function planFeatureLabel(feature) {
  if (feature == null) return "";
  if (typeof feature === "object" && feature !== null && "text" in feature) {
    return feature.text ?? "";
  }
  return feature;
}

export function planFeatureFontWeight(feature) {
  if (
    typeof feature === "object" &&
    feature !== null &&
    feature.bold === true
  ) {
    return "semibold";
  }
  return undefined;
}
