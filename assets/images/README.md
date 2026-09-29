# Bundled pictures

| File | What it is | Source | Licence |
| --- | --- | --- | --- |
| `sign_in_hero.jpg` | A mechanic on a motorcycle with a "Mobile Mechanic" top box, on a wet city street at night. "Book a Mechanic through our app" is painted into its top left, so Sign In puts no headline over it (`AuthPhoto.mobileMechanic`). 1324 × 1188. | An AI-generated picture the owner supplied on 2026-09-29, saved as JPEG at quality 85. | The owner's own picture, for use in the app. |
| `emergency_card.jpg` | A drawing of a mechanic in a cap kneeling to fix a cream scooter, on a white ground. The picture on the client home's emergency card, where a light theme multiplies it by the card's tint so its white takes the card's colour. 736 × 736. | Supplied by the owner on 2026-09-29 as `download.jpg`; where it came from is not recorded. | Not recorded. Confirm the right to use it before a public release. |
| `auth_hero.jpg` | A mechanic leaning into an engine bay in daylight. The hero of Forgot Password, darkened towards the sheet (`AuthPage` in `lib/widgets/auth_widgets.dart`). | [Pexels photo 8478259](https://www.pexels.com/photo/man-in-black-crew-neck-t-shirt-fixing-a-car-8478259/) by Sergey Meshkov, downloaded 2026-09-28 at 1600 px wide. | [Pexels License](https://www.pexels.com/license/): free to use and modify, commercially too, no attribution required. |

The admin console can publish a different photo for the sign-in pages (Settings > Change
Background); when it has, the app paints that one instead of the bundled one.

## Service icons

`services/` holds the icons on the home's service cards and chips, the booking and the job
cards (`MotorcycleProblem.picture` and `ServiceKind.picture` in
`lib/data/motorcycle_problem.dart`). Each is the 256 × 256 PNG from Flaticon, downloaded on
2026-09-29.

Flaticon's free licence allows use in the app, commercially too, on the condition that the
authors are credited. The app does that in Settings > Credits (`lib/data/service_icon_credits.dart`);
keep that credit while these icons ship. A Flaticon Premium subscription would drop the need
for it.

| File | Icon | Author | Flaticon id |
| --- | --- | --- | --- |
| `wont_start.png` | Spark plug | [Chattapat](https://www.flaticon.com/authors/chattapat) | [2417104](https://www.flaticon.com/free-icon/motorcycle_2417104) |
| `flat_tire.png` | Flat tire | Chattapat | [2582976](https://www.flaticon.com/free-icon/flat-tire_2582976) |
| `battery.png` | Battery | Chattapat | [2417009](https://www.flaticon.com/free-icon/motorcycle_2417009) |
| `chain.png` | Chain | Chattapat | [2417022](https://www.flaticon.com/free-icon/motorcycle_2417022) |
| `brakes.png` | Brake disc and caliper | Chattapat | [2417011](https://www.flaticon.com/free-icon/motorcycle_2417011) |
| `engine.png` | Piston | Chattapat | [2417080](https://www.flaticon.com/free-icon/motorcycle_2417080) |
| `electrical.png` | Control box and wiring | Chattapat | [2417035](https://www.flaticon.com/free-icon/motorcycle_2417035) |
| `overheating.png` | Radiator | Chattapat | [2417084](https://www.flaticon.com/free-icon/motorcycle_2417084) |
| `tune_up.png` | Speedometer | Chattapat | [2417107](https://www.flaticon.com/free-icon/motorcycle_2417107) |
| `towing.png` | Tow truck | Chattapat | [2474152](https://www.flaticon.com/free-icon/car-service_2474152) |
| `other.png` | Hand with a wrench | Chattapat | [2607826](https://www.flaticon.com/free-icon/maintenance_2607826) |
| `all.png` | Motorcycle (the "All" chip) | Chattapat | [2173605](https://www.flaticon.com/free-icon/motorcycle_2173605) |
| `oil_change.png` | Engine oil (also the "Maintenance" chip) | [surang](https://www.flaticon.com/authors/surang) | [5385698](https://www.flaticon.com/free-icon/engine-oil_5385698) |
| `repairs.png` | Motorcycle with a wrench (the "Repairs" chip) | [Smashicons](https://www.flaticon.com/authors/smashicons) | [3418144](https://www.flaticon.com/free-icon/bike_3418144) |
