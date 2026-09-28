import 'package:flutter/material.dart';

/// What can go wrong with a motorcycle, as the client picks it on the home
/// screen. On Go is motorcycle repair; this list is the whole menu.
///
/// The booking sends [label] as the request's problem line, and whatever the
/// client adds as its description.
enum MotorcycleProblem {
  wontStart(
    "Won't start",
    Icons.power_settings_new_rounded,
    'E.g. it clicks when I press the starter, or nothing happens at all.',
  ),
  flatTire(
    'Flat tire',
    Icons.tire_repair_rounded,
    'E.g. the rear tire went flat on the road; I may need a new interior.',
  ),
  batteryDead(
    'Battery dead',
    Icons.battery_alert_rounded,
    'E.g. the lights are dim and the horn is weak.',
  ),
  chain(
    'Chain problem',
    Icons.link_rounded,
    'E.g. the chain slipped off, or it is loose and noisy.',
  ),
  brakes(
    'Brake problem',
    Icons.album_rounded,
    'E.g. the front brake feels soft, or it squeals when I stop.',
  ),
  engine(
    'Engine problem',
    Icons.build_rounded,
    'E.g. it stalls at idle, smokes, or loses power going uphill.',
  ),
  electrical(
    'Electrical or lights',
    Icons.bolt_rounded,
    'E.g. the headlight is out, or the signal lights stopped working.',
  ),
  accident(
    'Accident or towing',
    Icons.car_crash_rounded,
    'E.g. I dropped the bike and it will not run; I need it moved.',
  ),
  somethingElse(
    'Something else',
    Icons.more_horiz_rounded,
    'Tell the mechanic what is happening, in your own words.',
  );

  const MotorcycleProblem(this.label, this.icon, this.detailsHint);

  /// As the client reads it on the tile and the mechanic in the request.
  final String label;

  /// The tile's glyph.
  final IconData icon;

  /// The example in the details field for this problem.
  final String detailsHint;

  /// "Something else" says nothing on its own, so the details are the
  /// problem there and must be given.
  bool get requiresDetails => this == MotorcycleProblem.somethingElse;
}
