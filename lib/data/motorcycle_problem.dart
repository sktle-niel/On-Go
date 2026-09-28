/// What a client can book a mechanic for, as picked on the home screen. On
/// Go is motorcycle repair; this list is the whole menu.
///
/// Each carries a picture rather than an icon font glyph: the tiles are the
/// product's front door and are drawn like a ride-hailing app's services.
///
/// The motorcycle beside the home greeting is [motorcyclePicture].
///
/// The booking sends [label] as the request's problem line, and whatever the
/// client adds as its description.
enum MotorcycleProblem {
  wontStart(
    "Won't start",
    "Won't start",
    'assets/images/problems/wont_start.png',
    'E.g. it clicks when I press the starter, or nothing happens at all.',
  ),
  flatTire(
    'Flat tire',
    'Flat tire',
    'assets/images/problems/flat_tire.png',
    'E.g. the rear tire went flat on the road; I may need a new interior.',
  ),
  batteryDead(
    'Battery dead',
    'Battery',
    'assets/images/problems/battery_dead.png',
    'E.g. the lights are dim and the horn is weak.',
  ),
  chain(
    'Chain problem',
    'Chain',
    'assets/images/problems/chain.png',
    'E.g. the chain slipped off, or it is loose and noisy.',
  ),
  brakes(
    'Brake problem',
    'Brakes',
    'assets/images/problems/brakes.png',
    'E.g. the front brake feels soft, or it squeals when I stop.',
  ),
  engine(
    'Engine problem',
    'Engine',
    'assets/images/problems/engine.png',
    'E.g. it stalls at idle, smokes, or loses power going uphill.',
  ),
  electrical(
    'Electrical or lights',
    'Electrical',
    'assets/images/problems/electrical.png',
    'E.g. the headlight is out, or the signal lights stopped working.',
  ),
  overheating(
    'Overheating',
    'Overheating',
    'assets/images/problems/overheating.png',
    'E.g. the engine gets very hot in traffic, or there is a burning smell.',
  ),
  oilChange(
    'Oil change',
    'Oil change',
    'assets/images/problems/oil_change.png',
    'E.g. it is due for a change; say the oil you use if you have a preference.',
  ),
  tuneUp(
    'Tune-up',
    'Tune-up',
    'assets/images/problems/tune_up.png',
    'E.g. a general check: carb or injection, spark plug, cables, tightening.',
  ),
  accident(
    'Accident or towing',
    'Towing',
    'assets/images/problems/accident.png',
    'E.g. I dropped the bike and it will not run; I need it moved.',
  ),
  somethingElse(
    'Something else',
    'Other',
    'assets/images/problems/something_else.png',
    'Tell the mechanic what is happening, in your own words.',
  );

  const MotorcycleProblem(this.label, this.shortLabel, this.picture, this.detailsHint);

  /// As the mechanic reads it in the request and the client in the booking.
  final String label;

  /// Under the tile, where there is room for a word or two.
  final String shortLabel;

  /// The tile's picture: a 3D render from Microsoft's Fluent Emoji set
  /// (MIT), see assets/images/README.md.
  final String picture;

  /// The example in the details field for this problem.
  final String detailsHint;

  /// "Something else" says nothing on its own, so the details are the
  /// problem there and must be given.
  bool get requiresDetails => this == MotorcycleProblem.somethingElse;

  /// The motorcycle itself, for the home greeting.
  static const String motorcyclePicture = 'assets/images/problems/motorcycle.png';

  /// The problem a request's line names, or null for one booked another way.
  static MotorcycleProblem? forLabel(String label) {
    for (final problem in values) {
      if (problem.label == label) return problem;
    }
    return null;
  }
}
