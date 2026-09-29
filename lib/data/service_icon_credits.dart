import 'package:flutter/foundation.dart';

/// The credit that Flaticon's free licence asks for, for the icons in
/// assets/images/services. Settings > Credits lists it with the licences of
/// the packages the app uses.
const serviceIconCredit = '''
The service icons come from Flaticon (www.flaticon.com) under its free licence, which asks for this credit.

Chattapat (www.flaticon.com/authors/chattapat): spark plug, flat tire, battery, chain, brake disc, piston, wiring, radiator, speedometer, tow truck, hand with a wrench, motorcycle.

surang (www.flaticon.com/authors/surang): engine oil.

Smashicons (www.flaticon.com/authors/smashicons): motorcycle with a wrench.''';

/// Adds [serviceIconCredit] to the app's licence list. Called once, from main.
void registerServiceIconCredits() {
  LicenseRegistry.addLicense(
    () => Stream.value(const LicenseEntryWithLineBreaks(['Flaticon icons'], serviceIconCredit)),
  );
}
