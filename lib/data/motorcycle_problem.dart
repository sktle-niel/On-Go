/// What can go wrong with a motorcycle, as the client picks it on the home
/// screen. On Go is motorcycle repair; this list is the whole menu.
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
    'assets/images/problems/wont_start.png',
    'E.g. it clicks when I press the starter, or nothing happens at all.',
  ),
  flatTire(
    'Flat tire',
    'assets/images/problems/flat_tire.png',
    'E.g. the rear tire went flat on the road; I may need a new interior.',
  ),
  batteryDead(
    'Battery dead',
    'assets/images/problems/battery_dead.png',
    'E.g. the lights are dim and the horn is weak.',
  ),
  chain(
    'Chain problem',
    'assets/images/problems/chain.png',
    'E.g. the chain slipped off, or it is loose and noisy.',
  ),
  brakes(
    'Brake problem',
    'assets/images/problems/brakes.png',
    'E.g. the front brake feels soft, or it squeals when I stop.',
  ),
  engine(
    'Engine problem',
    'assets/images/problems/engine.png',
    'E.g. it stalls at idle, smokes, or loses power going uphill.',
  ),
  electrical(
    'Electrical or lights',
    'assets/images/problems/electrical.png',
    'E.g. the headlight is out, or the signal lights stopped working.',
  ),
  accident(
    'Accident or towing',
    'assets/images/problems/accident.png',
    'E.g. I dropped the bike and it will not run; I need it moved.',
  ),
  somethingElse(
    'Something else',
    'assets/images/problems/something_else.png',
    'Tell the mechanic what is happening, in your own words.',
  );

  const MotorcycleProblem(this.label, this.picture, this.detailsHint);

  /// As the client reads it on the tile and the mechanic in the request.
  final String label;

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
