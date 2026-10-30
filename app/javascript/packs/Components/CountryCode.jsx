import React, { useState, useCallback, useContext } from "react";
import I18n from "../i18n-lang";

const rawCountryCode = [
  {
  "name": "Afghanistan",
  "label": "+93",
  "value": "AF"
  },
  {
  "name": "Aland Islands",
  "label": "+358",
  "value": "AX"
  },
  {
  "name": "Albania",
  "label": "+355",
  "value": "AL"
  },
  {
  "name": "Algeria",
  "label": "+213",
  "value": "DZ"
  },
  {
  "name": "AmericanSamoa",
  "label": "+1684",
  "value": "AS"
  },
  {
  "name": "Andorra",
  "label": "+376",
  "value": "AD"
  },
  {
  "name": "Angola",
  "label": "+244",
  "value": "AO"
  },
  {
  "name": "Anguilla",
  "label": "+1264",
  "value": "AI"
  },
  {
  "name": "Antarctica",
  "label": "+672",
  "value": "AQ"
  },
  {
  "name": "Antigua and Barbuda",
  "label": "+1268",
  "value": "AG"
  },
  {
  "name": "Argentina",
  "label": "+54",
  "value": "AR"
  },
  {
  "name": "Armenia",
  "label": "+374",
  "value": "AM"
  },
  {
  "name": "Aruba",
  "label": "+297",
  "value": "AW"
  },
  {
  "name": "Australia",
  "label": "+61",
  "value": "AU"
  },
  {
  "name": "Austria",
  "label": "+43",
  "value": "AT"
  },
  {
  "name": "Azerbaijan",
  "label": "+994",
  "value": "AZ"
  },
  {
  "name": "Bahamas",
  "label": "+1242",
  "value": "BS"
  },
  {
  "name": "Bahrain",
  "label": "+973",
  "value": "BH"
  },
  {
  "name": "Bangladesh",
  "label": "+880",
  "value": "BD"
  },
  {
  "name": "Barbados",
  "label": "+1246",
  "value": "BB"
  },
  {
  "name": "Belarus",
  "label": "+375",
  "value": "BY"
  },
  {
  "name": "Belgium",
  "label": "+32",
  "value": "BE"
  },
  {
  "name": "Belize",
  "label": "+501",
  "value": "BZ"
  },
  {
  "name": "Benin",
  "label": "+229",
  "value": "BJ"
  },
  {
  "name": "Bermuda",
  "label": "+1441",
  "value": "BM"
  },
  {
  "name": "Bhutan",
  "label": "+975",
  "value": "BT"
  },
  {
  "name": "Bolivia, Plurinational State of",
  "label": "+591",
  "value": "BO"
  },
  {
  "name": "Bosnia and Herzegovina",
  "label": "+387",
  "value": "BA"
  },
  {
  "name": "Botswana",
  "label": "+267",
  "value": "BW"
  },
  {
  "name": "Brazil",
  "label": "+55",
  "value": "BR"
  },
  {
  "name": "British Indian Ocean Territory",
  "label": "+246",
  "value": "IO"
  },
  {
  "name": "Brunei Darussalam",
  "label": "+673",
  "value": "BN"
  },
  {
  "name": "Bulgaria",
  "label": "+359",
  "value": "BG"
  },
  {
  "name": "Burkina Faso",
  "label": "+226",
  "value": "BF"
  },
  {
  "name": "Burundi",
  "label": "+257",
  "value": "BI"
  },
  {
  "name": "Cambodia",
  "label": "+855",
  "value": "KH"
  },
  {
  "name": "Cameroon",
  "label": "+237",
  "value": "CM"
  },
  {
  "name": "Canada",
  "label": "+1",
  "value": "CA"
  },
  {
  "name": "Cape Verde",
  "label": "+238",
  "value": "CV"
  },
  {
  "name": "Cayman Islands",
  "label": "+ 345",
  "value": "KY"
  },
  {
  "name": "Central African Republic",
  "label": "+236",
  "value": "CF"
  },
  {
  "name": "Chad",
  "label": "+235",
  "value": "TD"
  },
  {
  "name": "Chile",
  "label": "+56",
  "value": "CL"
  },
  {
  "name": "China",
  "label": "+86",
  "value": "CN"
  },
  {
  "name": "Christmas Island",
  "label": "+61",
  "value": "CX"
  },
  {
  "name": "Cocos (Keeling) Islands",
  "label": "+61",
  "value": "CC"
  },
  {
  "name": "Colombia",
  "label": "+57",
  "value": "CO"
  },
  {
  "name": "Comoros",
  "label": "+269",
  "value": "KM"
  },
  {
  "name": "Congo",
  "label": "+242",
  "value": "CG"
  },
  {
  "name": "Congo, The Democratic Republic of the Congo",
  "label": "+243",
  "value": "CD"
  },
  {
  "name": "Cook Islands",
  "label": "+682",
  "value": "CK"
  },
  {
  "name": "Costa Rica",
  "label": "+506",
  "value": "CR"
  },
  {
  "name": "Cote d'Ivoire",
  "label": "+225",
  "value": "CI"
  },
  {
  "name": "Croatia",
  "label": "+385",
  "value": "HR"
  },
  {
  "name": "Cuba",
  "label": "+53",
  "value": "CU"
  },
  {
  "name": "Cyprus",
  "label": "+357",
  "value": "CY"
  },
  {
  "name": "Czech Republic",
  "label": "+420",
  "value": "CZ"
  },
  {
  "name": "Denmark",
  "label": "+45",
  "value": "DK"
  },
  {
  "name": "Djibouti",
  "label": "+253",
  "value": "DJ"
  },
  {
  "name": "Dominica",
  "label": "+1767",
  "value": "DM"
  },
  {
  "name": "Dominican Republic",
  "label": "+1849",
  "value": "DO"
  },
  {
  "name": "Ecuador",
  "label": "+593",
  "value": "EC"
  },
  {
  "name": "Egypt",
  "label": "+20",
  "value": "EG"
  },
  {
  "name": "El Salvador",
  "label": "+503",
  "value": "SV"
  },
  {
  "name": "Equatorial Guinea",
  "label": "+240",
  "value": "GQ"
  },
  {
  "name": "Eritrea",
  "label": "+291",
  "value": "ER"
  },
  {
  "name": "Estonia",
  "label": "+372",
  "value": "EE"
  },
  {
  "name": "Ethiopia",
  "label": "+251",
  "value": "ET"
  },
  {
  "name": "Falkland Islands (Malvinas)",
  "label": "+500",
  "value": "FK"
  },
  {
  "name": "Faroe Islands",
  "label": "+298",
  "value": "FO"
  },
  {
  "name": "Fiji",
  "label": "+679",
  "value": "FJ"
  },
  {
  "name": "Finland",
  "label": "+358",
  "value": "FI"
  },
  {
  "name": "France",
  "label": "+33",
  "value": "FR"
  },
  {
  "name": "French Guiana",
  "label": "+594",
  "value": "GF"
  },
  {
  "name": "French Polynesia",
  "label": "+689",
  "value": "PF"
  },
  {
  "name": "Gabon",
  "label": "+241",
  "value": "GA"
  },
  {
  "name": "Gambia",
  "label": "+220",
  "value": "GM"
  },
  {
  "name": "Georgia",
  "label": "+995",
  "value": "GE"
  },
  {
  "name": "Germany",
  "label": "+49",
  "value": "DE"
  },
  {
  "name": "Ghana",
  "label": "+233",
  "value": "GH"
  },
  {
  "name": "Gibraltar",
  "label": "+350",
  "value": "GI"
  },
  {
  "name": "Greece",
  "label": "+30",
  "value": "GR"
  },
  {
  "name": "Greenland",
  "label": "+299",
  "value": "GL"
  },
  {
  "name": "Grenada",
  "label": "+1473",
  "value": "GD"
  },
  {
  "name": "Guadeloupe",
  "label": "+590",
  "value": "GP"
  },
  {
  "name": "Guam",
  "label": "+1671",
  "value": "GU"
  },
  {
  "name": "Guatemala",
  "label": "+502",
  "value": "GT"
  },
  {
  "name": "Guernsey",
  "label": "+44",
  "value": "GG"
  },
  {
  "name": "Guinea",
  "label": "+224",
  "value": "GN"
  },
  {
  "name": "Guinea-Bissau",
  "label": "+245",
  "value": "GW"
  },
  {
  "name": "Guyana",
  "label": "+595",
  "value": "GY"
  },
  {
  "name": "Haiti",
  "label": "+509",
  "value": "HT"
  },
  {
  "name": "Holy See (Vatican City State)",
  "label": "+379",
  "value": "VA"
  },
  {
  "name": "Honduras",
  "label": "+504",
  "value": "HN"
  },
  {
  "name": "Hong Kong",
  "label": "+852",
  "value": "HK"
  },
  {
  "name": "Hungary",
  "label": "+36",
  "value": "HU"
  },
  {
  "name": "Iceland",
  "label": "+354",
  "value": "IS"
  },
  {
  "name": "India",
  "label": "+91",
  "value": "IN"
  },
  {
  "name": "Indonesia",
  "label": "+62",
  "value": "ID"
  },
  {
  "name": "Iran, Islamic Republic of Persian Gulf",
  "label": "+98",
  "value": "IR"
  },
  {
  "name": "Iraq",
  "label": "+964",
  "value": "IQ"
  },
  {
  "name": "Ireland",
  "label": "+353",
  "value": "IE"
  },
  {
  "name": "Isle of Man",
  "label": "+44",
  "value": "IM"
  },
  {
  "name": "Israel",
  "label": "+972",
  "value": "IL"
  },
  {
  "name": "Italy",
  "label": "+39",
  "value": "IT"
  },
  {
  "name": "Jamaica",
  "label": "+1876",
  "value": "JM"
  },
  {
  "name": "Japan",
  "label": "+81",
  "value": "JP"
  },
  {
  "name": "Jersey",
  "label": "+44",
  "value": "JE"
  },
  {
  "name": "Jordan",
  "label": "+962",
  "value": "JO"
  },
  {
  "name": "Kazakhstan",
  "label": "+77",
  "value": "KZ"
  },
  {
  "name": "Kenya",
  "label": "+254",
  "value": "KE"
  },
  {
  "name": "Kiribati",
  "label": "+686",
  "value": "KI"
  },
  {
  "name": "Korea, Democratic People's Republic of Korea",
  "label": "+850",
  "value": "KP"
  },
  {
  "name": "Korea, Republic of South Korea",
  "label": "+82",
  "value": "KR"
  },
  {
  "name": "Kuwait",
  "label": "+965",
  "value": "KW"
  },
  {
  "name": "Kyrgyzstan",
  "label": "+996",
  "value": "KG"
  },
  {
  "name": "Laos",
  "label": "+856",
  "value": "LA"
  },
  {
  "name": "Latvia",
  "label": "+371",
  "value": "LV"
  },
  {
  "name": "Lebanon",
  "label": "+961",
  "value": "LB"
  },
  {
  "name": "Lesotho",
  "label": "+266",
  "value": "LS"
  },
  {
  "name": "Liberia",
  "label": "+231",
  "value": "LR"
  },
  {
  "name": "Libyan Arab Jamahiriya",
  "label": "+218",
  "value": "LY"
  },
  {
  "name": "Liechtenstein",
  "label": "+423",
  "value": "LI"
  },
  {
  "name": "Lithuania",
  "label": "+370",
  "value": "LT"
  },
  {
  "name": "Luxembourg",
  "label": "+352",
  "value": "LU"
  },
  {
  "name": "Macao",
  "label": "+853",
  "value": "MO"
  },
  {
  "name": "Macedonia",
  "label": "+389",
  "value": "MK"
  },
  {
  "name": "Madagascar",
  "label": "+261",
  "value": "MG"
  },
  {
  "name": "Malawi",
  "label": "+265",
  "value": "MW"
  },
  {
  "name": "Malaysia",
  "label": "+60",
  "value": "MY"
  },
  {
  "name": "Maldives",
  "label": "+960",
  "value": "MV"
  },
  {
  "name": "Mali",
  "label": "+223",
  "value": "ML"
  },
  {
  "name": "Malta",
  "label": "+356",
  "value": "MT"
  },
  {
  "name": "Marshall Islands",
  "label": "+692",
  "value": "MH"
  },
  {
  "name": "Martinique",
  "label": "+596",
  "value": "MQ"
  },
  {
  "name": "Mauritania",
  "label": "+222",
  "value": "MR"
  },
  {
  "name": "Mauritius",
  "label": "+230",
  "value": "MU"
  },
  {
  "name": "Mayotte",
  "label": "+262",
  "value": "YT"
  },
  {
  "name": "Mexico",
  "label": "+52",
  "value": "MX"
  },
  {
  "name": "Micronesia, Federated States of Micronesia",
  "label": "+691",
  "value": "FM"
  },
  {
  "name": "Moldova",
  "label": "+373",
  "value": "MD"
  },
  {
  "name": "Monaco",
  "label": "+377",
  "value": "MC"
  },
  {
  "name": "Mongolia",
  "label": "+976",
  "value": "MN"
  },
  {
  "name": "Montenegro",
  "label": "+382",
  "value": "ME"
  },
  {
  "name": "Montserrat",
  "label": "+1664",
  "value": "MS"
  },
  {
  "name": "Morocco",
  "label": "+212",
  "value": "MA"
  },
  {
  "name": "Mozambique",
  "label": "+258",
  "value": "MZ"
  },
  {
  "name": "Myanmar",
  "label": "+95",
  "value": "MM"
  },
  {
  "name": "Namibia",
  "label": "+264",
  "value": "NA"
  },
  {
  "name": "Nauru",
  "label": "+674",
  "value": "NR"
  },
  {
  "name": "Nepal",
  "label": "+977",
  "value": "NP"
  },
  {
  "name": "Netherlands",
  "label": "+31",
  "value": "NL"
  },
  {
  "name": "Netherlands Antilles",
  "label": "+599",
  "value": "AN"
  },
  {
  "name": "New Caledonia",
  "label": "+687",
  "value": "NC"
  },
  {
  "name": "New Zealand",
  "label": "+64",
  "value": "NZ"
  },
  {
  "name": "Nicaragua",
  "label": "+505",
  "value": "NI"
  },
  {
  "name": "Niger",
  "label": "+227",
  "value": "NE"
  },
  {
  "name": "Nigeria",
  "label": "+234",
  "value": "NG"
  },
  {
  "name": "Niue",
  "label": "+683",
  "value": "NU"
  },
  {
  "name": "Norfolk Island",
  "label": "+672",
  "value": "NF"
  },
  {
  "name": "Northern Mariana Islands",
  "label": "+1670",
  "value": "MP"
  },
  {
  "name": "Norway",
  "label": "+47",
  "value": "NO"
  },
  {
  "name": "Oman",
  "label": "+968",
  "value": "OM"
  },
  {
  "name": "Pakistan",
  "label": "+92",
  "value": "PK"
  },
  {
  "name": "Palau",
  "label": "+680",
  "value": "PW"
  },
  {
  "name": "Palestinian Territory, Occupied",
  "label": "+970",
  "value": "PS"
  },
  {
  "name": "Panama",
  "label": "+507",
  "value": "PA"
  },
  {
  "name": "Papua New Guinea",
  "label": "+675",
  "value": "PG"
  },
  {
  "name": "Paraguay",
  "label": "+595",
  "value": "PY"
  },
  {
  "name": "Peru",
  "label": "+51",
  "value": "PE"
  },
  {
  "name": "Philippines",
  "label": "+63",
  "value": "PH"
  },
  {
  "name": "Pitcairn",
  "label": "+872",
  "value": "PN"
  },
  {
  "name": "Poland",
  "label": "+48",
  "value": "PL"
  },
  {
  "name": "Portugal",
  "label": "+351",
  "value": "PT"
  },
  {
  "name": "Puerto Rico",
  "label": "+1939",
  "value": "PR"
  },
  {
  "name": "Qatar",
  "label": "+974",
  "value": "QA"
  },
  {
  "name": "Romania",
  "label": "+40",
  "value": "RO"
  },
  {
  "name": "Russia",
  "label": "+7",
  "value": "RU"
  },
  {
  "name": "Rwanda",
  "label": "+250",
  "value": "RW"
  },
  {
  "name": "Reunion",
  "label": "+262",
  "value": "RE"
  },
  {
  "name": "Saint Barthelemy",
  "label": "+590",
  "value": "BL"
  },
  {
  "name": "Saint Helena, Ascension and Tristan Da Cunha",
  "label": "+290",
  "value": "SH"
  },
  {
  "name": "Saint Kitts and Nevis",
  "label": "+1869",
  "value": "KN"
  },
  {
  "name": "Saint Lucia",
  "label": "+1758",
  "value": "LC"
  },
  {
  "name": "Saint Martin",
  "label": "+590",
  "value": "MF"
  },
  {
  "name": "Saint Pierre and Miquelon",
  "label": "+508",
  "value": "PM"
  },
  {
  "name": "Saint Vincent and the Grenadines",
  "label": "+1784",
  "value": "VC"
  },
  {
  "name": "Samoa",
  "label": "+685",
  "value": "WS"
  },
  {
  "name": "San Marino",
  "label": "+378",
  "value": "SM"
  },
  {
  "name": "Sao Tome and Principe",
  "label": "+239",
  "value": "ST"
  },
  {
  "name": "Saudi Arabia",
  "label": "+966",
  "value": "SA"
  },
  {
  "name": "Senegal",
  "label": "+221",
  "value": "SN"
  },
  {
  "name": "Serbia",
  "label": "+381",
  "value": "RS"
  },
  {
  "name": "Seychelles",
  "label": "+248",
  "value": "SC"
  },
  {
  "name": "Sierra Leone",
  "label": "+232",
  "value": "SL"
  },
  {
  "name": "Singapore",
  "label": "+65",
  "value": "SG"
  },
  {
  "name": "Slovakia",
  "label": "+421",
  "value": "SK"
  },
  {
  "name": "Slovenia",
  "label": "+386",
  "value": "SI"
  },
  {
  "name": "Solomon Islands",
  "label": "+677",
  "value": "SB"
  },
  {
  "name": "Somalia",
  "label": "+252",
  "value": "SO"
  },
  {
  "name": "South Africa",
  "label": "+27",
  "value": "ZA"
  },
  {
  "name": "South Sudan",
  "label": "+211",
  "value": "SS"
  },
  {
  "name": "South Georgia and the South Sandwich Islands",
  "label": "+500",
  "value": "GS"
  },
  {
  "name": "Spain",
  "label": "+34",
  "value": "ES"
  },
  {
  "name": "Sri Lanka",
  "label": "+94",
  "value": "LK"
  },
  {
  "name": "Sudan",
  "label": "+249",
  "value": "SD"
  },
  {
  "name": "Suriname",
  "label": "+597",
  "value": "SR"
  },
  {
  "name": "Svalbard and Jan Mayen",
  "label": "+47",
  "value": "SJ"
  },
  {
  "name": "Swaziland",
  "label": "+268",
  "value": "SZ"
  },
  {
  "name": "Sweden",
  "label": "+46",
  "value": "SE"
  },
  {
  "name": "Switzerland",
  "label": "+41",
  "value": "CH"
  },
  {
  "name": "Syrian Arab Republic",
  "label": "+963",
  "value": "SY"
  },
  {
  "name": "Taiwan",
  "label": "+886",
  "value": "TW"
  },
  {
  "name": "Tajikistan",
  "label": "+992",
  "value": "TJ"
  },
  {
  "name": "Tanzania, United Republic of Tanzania",
  "label": "+255",
  "value": "TZ"
  },
  {
  "name": "Thailand",
  "label": "+66",
  "value": "TH"
  },
  {
  "name": "Timor-Leste",
  "label": "+670",
  "value": "TL"
  },
  {
  "name": "Togo",
  "label": "+228",
  "value": "TG"
  },
  {
  "name": "Tokelau",
  "label": "+690",
  "value": "TK"
  },
  {
  "name": "Tonga",
  "label": "+676",
  "value": "TO"
  },
  {
  "name": "Trinidad and Tobago",
  "label": "+1868",
  "value": "TT"
  },
  {
  "name": "Tunisia",
  "label": "+216",
  "value": "TN"
  },
  {
  "name": "Turkey",
  "label": "+90",
  "value": "TR"
  },
  {
  "name": "Turkmenistan",
  "label": "+993",
  "value": "TM"
  },
  {
  "name": "Turks and Caicos Islands",
  "label": "+1649",
  "value": "TC"
  },
  {
  "name": "Tuvalu",
  "label": "+688",
  "value": "TV"
  },
  {
  "name": "Uganda",
  "label": "+256",
  "value": "UG"
  },
  {
  "name": "Ukraine",
  "label": "+380",
  "value": "UA"
  },
  {
  "name": "United Arab Emirates",
  "label": "+971",
  "value": "AE"
  },
  {
  "name": "United Kingdom",
  "label": "+44",
  "value": "GB"
  },
  {
  "name": "United States",
  "label": "+1",
  "value": "US"
  },
  {
  "name": "Uruguay",
  "label": "+598",
  "value": "UY"
  },
  {
  "name": "Uzbekistan",
  "label": "+998",
  "value": "UZ"
  },
  {
  "name": "Vanuatu",
  "label": "+678",
  "value": "VU"
  },
  {
  "name": "Venezuela, Bolivarian Republic of Venezuela",
  "label": "+58",
  "value": "VE"
  },
  {
  "name": "Vietnam",
  "label": "+84",
  "value": "VN"
  },
  {
  "name": "Virgin Islands, British",
  "label": "+1284",
  "value": "VG"
  },
  {
  "name": "Virgin Islands, U.S.",
  "label": "+1340",
  "value": "VI"
  },
  {
  "name": "Wallis and Futuna",
  "label": "+681",
  "value": "WF"
  },
  {
  "name": "Yemen",
  "label": "+967",
  "value": "YE"
  },
  {
  "name": "Zambia",
  "label": "+260",
  "value": "ZM"
  },
  {
  "name": "Zimbabwe",
  "label": "+263",
  "value": "ZW"
  }
  ]
// `label` here is the dial code (+93) and must never be translated. Only
// `name` is the country, resolved lazily against the active locale.
const CountryCode = rawCountryCode.map((c) => ({
  label: c.label,
  value: c.value,
  get name() {
    return I18n.t(`countries.${c.value}`, { defaultValue: c.name });
  },
}));

export default CountryCode;