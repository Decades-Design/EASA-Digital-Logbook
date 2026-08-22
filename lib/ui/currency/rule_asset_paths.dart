/// Every rule file the app loads at start-up — see `assets/rules/README.md`.
/// Shared by the Currency and Settings screens: Currency loads the full set
/// rather than only the ids `sampleCurrencyLicences` happens to reference
/// (keeps this list from needing to track the sample fixture's own
/// choices); Settings' "Rule set in use" figure needs the same complete set
/// to summarize.
const ruleAssetPaths = [
  'assets/rules/easa/fcl060_b1_passenger_recency.yaml',
  'assets/rules/easa/fcl060_b3_night_passenger_recency.yaml',
  'assets/rules/easa/fcl740a_sep_land_revalidation.yaml',
  'assets/rules/easa/med_a045_class1_validity.yaml',
  'assets/rules/easa/med_a045_class2_validity.yaml',
  'assets/rules/faa/61_23_first_class_medical_validity.yaml',
  'assets/rules/faa/61_23_second_class_medical_validity.yaml',
  'assets/rules/faa/61_23_third_class_medical_validity.yaml',
  'assets/rules/faa/61_56_flight_review.yaml',
  'assets/rules/faa/61_57_a2_tailwheel_takeoff_landing_currency.yaml',
  'assets/rules/faa/61_57_a_takeoff_landing_currency.yaml',
  'assets/rules/faa/61_57_b_night_takeoff_landing_currency.yaml',
  'assets/rules/faa/61_57_c_instrument_currency.yaml',
  'assets/rules/faa/61_57_c_instrument_currency_grace_period.yaml',
];
