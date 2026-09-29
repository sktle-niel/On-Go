import 'package:flutter/material.dart';

/// Which chip on the home screen a service sits under.
enum ServiceKind {
  repair('Repairs', Icons.build_rounded),
  maintenance('Maintenance', Icons.oil_barrel_rounded),
  towing('Towing', Icons.local_shipping_rounded),

  /// Listed under "All" only.
  other('Other', Icons.handyman_rounded);

  const ServiceKind(this.label, this.icon);

  final String label;
  final IconData icon;
}

/// What a client can book a mechanic for, as picked on the home screen. On
/// Go is motorcycle repair; this list is the whole menu.
///
/// Each carries a glyph for the home screen's service cards and the job
/// cards, a [kind] for the home screen's chips, and a [blurb] that says in a
/// line what the mechanic does about it.
///
/// The booking sends [label] as the request's problem line, and whatever the
/// client adds as its description.
enum MotorcycleProblem {
  wontStart(
    "Won't start",
    "Won't start",
    Icons.power_settings_new_rounded,
    'E.g. it clicks when I press the starter, or nothing happens at all.',
    ServiceKind.repair,
    'Starter, spark and fuel checks on the spot',
  ),
  flatTire(
    'Flat tire',
    'Flat tire',
    Icons.tire_repair_rounded,
    'E.g. the rear tire went flat on the road; I may need a new interior.',
    ServiceKind.repair,
    'Patch or replace the tube where you stopped',
  ),
  batteryDead(
    'Battery dead',
    'Battery',
    Icons.battery_alert_rounded,
    'E.g. the lights are dim and the horn is weak.',
    ServiceKind.repair,
    'A jump start or a new battery',
  ),
  chain(
    'Chain problem',
    'Chain',
    Icons.link_rounded,
    'E.g. the chain slipped off, or it is loose and noisy.',
    ServiceKind.repair,
    'Tighten, refit or replace the chain',
  ),
  brakes(
    'Brake problem',
    'Brakes',
    Icons.album_rounded,
    'E.g. the front brake feels soft, or it squeals when I stop.',
    ServiceKind.repair,
    'Brake pads, cables and fluid',
  ),
  engine(
    'Engine problem',
    'Engine',
    Icons.settings_rounded,
    'E.g. it stalls at idle, smokes, or loses power going uphill.',
    ServiceKind.repair,
    'Stalling, smoke or lost power',
  ),
  electrical(
    'Electrical or lights',
    'Electrical',
    Icons.bolt_rounded,
    'E.g. the headlight is out, or the signal lights stopped working.',
    ServiceKind.repair,
    'Lights, signals and wiring',
  ),
  overheating(
    'Overheating',
    'Overheating',
    Icons.thermostat_rounded,
    'E.g. the engine gets very hot in traffic, or there is a burning smell.',
    ServiceKind.repair,
    'Coolant, fan and temperature checks',
  ),
  oilChange(
    'Oil change',
    'Oil change',
    Icons.oil_barrel_rounded,
    'E.g. it is due for a change; say the oil you use if you have a preference.',
    ServiceKind.maintenance,
    'Fresh engine oil and a new filter',
  ),
  tuneUp(
    'Tune-up',
    'Tune-up',
    Icons.tune_rounded,
    'E.g. a general check: carb or injection, spark plug, cables, tightening.',
    ServiceKind.maintenance,
    'Spark plug, cables and a full check',
  ),
  accident(
    'Accident or towing',
    'Towing',
    Icons.local_shipping_rounded,
    'E.g. I dropped the bike and it will not run; I need it moved.',
    ServiceKind.towing,
    'Your mechanic moves the bike to a shop',
  ),
  somethingElse(
    'Something else',
    'Other',
    Icons.handyman_rounded,
    'Tell the mechanic what is happening, in your own words.',
    ServiceKind.other,
    'Describe it in your own words',
  );

  const MotorcycleProblem(this.label, this.shortLabel, this.icon, this.detailsHint, this.kind, this.blurb);

  /// As the mechanic reads it in the request and the client in the booking.
  final String label;

  /// Under the tile, where there is room for a word or two.
  final String shortLabel;

  /// The glyph on the tile and the card.
  final IconData icon;

  /// The example in the details field for this problem.
  final String detailsHint;

  /// The home screen chip it sits under.
  final ServiceKind kind;

  /// What the mechanic does about it, in a line, on the home screen's card.
  final String blurb;

  /// "Something else" says nothing on its own, so the details are the
  /// problem there and must be given.
  bool get requiresDetails => this == MotorcycleProblem.somethingElse;

  /// The problem a request's line names, or null for one booked another way.
  static MotorcycleProblem? forLabel(String label) {
    for (final problem in values) {
      if (problem.label == label) return problem;
    }
    return null;
  }
}
