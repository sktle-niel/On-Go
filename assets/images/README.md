# Bundled pictures

| File | What it is | Source | Licence |
| --- | --- | --- | --- |
| `sign_in_hero.jpg` | A mechanic on a motorcycle with a "Mobile Mechanic" top box, on a wet city street at night. "Book a Mechanic through our app" is painted into its top left, so Sign In puts no headline over it (`AuthPhoto.mobileMechanic`). 1324 × 1188. | An AI-generated picture the owner supplied on 2026-09-29, saved as JPEG at quality 85. | The owner's own picture, for use in the app. |
| `emergency_card.jpg` | The same picture cropped to the mechanic and the top box, clear of the painted words: the pixels from (530, 300), 794 × 888, scaled to 397 × 444. The picture on the client home's emergency card. | Cropped from `sign_in_hero.jpg` on 2026-09-29, JPEG at quality 85. | As `sign_in_hero.jpg`. |
| `auth_hero.jpg` | A mechanic leaning into an engine bay in daylight. The hero of Forgot Password, darkened towards the sheet (`AuthPage` in `lib/widgets/auth_widgets.dart`). | [Pexels photo 8478259](https://www.pexels.com/photo/man-in-black-crew-neck-t-shirt-fixing-a-car-8478259/) by Sergey Meshkov, downloaded 2026-09-28 at 1600 px wide. | [Pexels License](https://www.pexels.com/license/): free to use and modify, commercially too, no attribution required. |

The admin console can publish a different photo for the sign-in pages (Settings > Change
Background); when it has, the app paints that one instead of the bundled one.
