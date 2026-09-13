import 'package:flutter/material.dart';
import 'data/mechanic_settings_store.dart';
import 'data/points_policy_store.dart';
import 'data/registration_draft.dart';
import 'services/location/location_service.dart';
import 'services/location/place_sources.dart';
import 'services/location/platform_reverse_geocoder.dart';
import 'services/location/psgc_place_directory.dart';
import 'screens/auth/mechanic_registration/mechanic_step4_documents.dart';
import 'screens/auth/mechanic_registration/mechanic_step5_verification.dart';
import 'screens/auth/sign_in_screen.dart';
import 'theme/app_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Restore the saved theme before the first frame so the app never flashes
  // the Default palette on startup.
  await ThemeController.instance.load();
  // Same for the background photo published from the admin console, so the
  // Sign In screen paints it on the first frame instead of flashing the
  // background color first.
  await AuthBackgroundController.instance.load();
  // And the mechanic's own preferences, so the Emergency pulse toggle is
  // whatever they last set it to.
  await MechanicSettingsStore.instance.load();
  // The points rules the console configures. Loaded before the first frame so
  // a payment settled early in the session awards the right amount.
  await PointsPolicyStore.instance.load();
  // The registration draft, so a launch that is really Android restarting us
  // mid-photo-pick can put the user back on the form rather than Sign In.
  await RegistrationDraft.instance.load();
  // Location: whether the user has already been asked, the last fix this
  // device took, and the permission as it stands now. Never prompts — the
  // one-time prompt waits until a Client or Mechanic has signed in.
  await LocationService.instance.load();
  // Place names: the PSA's official list bundled with the app, and the
  // phone's own geocoder for turning a GPS fix into an address. Both load
  // lazily, and both report themselves unavailable rather than failing — the
  // directory until its asset has been built and added, the geocoder when
  // the device is offline or has none.
  PlaceSources.configure(
    directory: PsgcPlaceDirectory(),
    geocoder: PlatformReverseGeocoder(),
  );
  runApp(MyApp(resumeRegistrationStep: RegistrationDraft.instance.pendingPickerStep));
}

class MyApp extends StatefulWidget {
  /// The mechanic registration step to reopen on this launch, or 0 for a
  /// normal start at Sign In.
  ///
  /// Non-zero means the previous run was killed by Android while a photo
  /// picker was in front of it (see [RegistrationDraft.pendingPickerStep]) —
  /// the user is mid-registration, not starting the app.
  final int resumeRegistrationStep;

  const MyApp({super.key, this.resumeRegistrationStep = 0});

  // This widget is the root of your application.
  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  final _themeController = ThemeController.instance;

  /// The palette last repainted for, so [_onThemeChanged] can tell a real
  /// theme switch from a Warm Filter drag.
  String _lastThemeId = ThemeController.instance.selectedId;
  final _navigatorKey = GlobalKey<NavigatorState>();

  @override
  void initState() {
    super.initState();
    _themeController.addListener(_onThemeChanged);
    if (widget.resumeRegistrationStep > 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _resumeRegistration());
    }
  }

  /// Puts the interrupted registration back on screen. Step 4 goes underneath
  /// so Back still walks the form in order; every step rebuilds itself from
  /// the saved draft, so nothing the user typed is lost. The step clears the
  /// pending-picker flag once it has recovered the photo.
  void _resumeRegistration() {
    final navigator = _navigatorKey.currentState;
    if (navigator == null) return;
    navigator.push(MaterialPageRoute(builder: (_) => const MechanicStep4Documents()));
    navigator.push(MaterialPageRoute(builder: (_) => const MechanicStep5Verification()));
  }

  @override
  void dispose() {
    _themeController.removeListener(_onThemeChanged);
    super.dispose();
  }

  void _onThemeChanged() {
    if (!mounted) return;
    setState(() {});

    // Screens read their colors from `AppColors`, a plain static lookup rather
    // than an InheritedWidget dependency. Routes already on the Navigator
    // stack cache their subtree, so rebuilding MaterialApp on its own would
    // not repaint the screens sitting behind the Themes screen. Marking the
    // whole tree dirty (what a hot reload does) repaints every open screen
    // without disturbing navigation or screen state.
    //
    // Only worth doing when the palette actually changed, though. The Warm
    // Filter is continuous, so a single drag notifies on every frame, and it
    // needs nothing but the tint above — which the builder below applies from
    // this state's own rebuild. Walking the whole tree sixty times a second
    // for it would make dragging crawl.
    final themeId = _themeController.selectedId;
    if (themeId != _lastThemeId) {
      _lastThemeId = themeId;
      _rebuildEverything(context as Element);
    }
  }

  void _rebuildEverything(Element element) {
    element.markNeedsBuild();
    element.visitChildren(_rebuildEverything);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Demo',
      navigatorKey: _navigatorKey,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.themeFor(_themeController.selected),
      // Everything that has to sit above every route, sheet and dialog is
      // installed here, in one place, rather than remembered screen by screen.
      builder: (context, child) {
        final content = child ?? const SizedBox.shrink();
        final media = MediaQuery.of(context);
        final layout = AppLayout.fromSize(media.size);

        // Text sizing, settled once for the whole app.
        //
        // Two things at once. The reader's own font-size setting is honoured
        // but bounded — these screens carry fixed heights and single-line
        // labels that genuinely break at the 2x some devices can ask for, and
        // a bounded enlargement beats an unusable screen. On top of that, a
        // gentle per-device factor: a little smaller on a small phone so long
        // labels fit, a little larger on a tablet, which is held further away.
        //
        // Doing it here rather than in the theme is what makes it reach the
        // hundreds of literal `fontSize:` values still scattered through the
        // screens — those ignore the TextTheme, but nothing ignores this.
        final sized = MediaQuery(
          data: media.copyWith(textScaler: layout.textScalerFrom(media.textScaler)),
          child: AppLayoutScope(layout: layout, child: content),
        );

        // The Warm Filter tints everything below in one compositing pass.
        final tint = AppTheme.warmFilterTint(_themeController.warmFilter);
        if (tint == null) return sized;
        return ColorFiltered(
          colorFilter: ColorFilter.mode(tint, BlendMode.modulate),
          child: sized,
        );
      },
      home: SignInScreen(),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});

  // This widget is the home page of your application. It is stateful, meaning
  // that it has a State object (defined below) that contains fields that affect
  // how it looks.

  // This class is the configuration for the state. It holds the values (in this
  // case the title) provided by the parent (in this case the App widget) and
  // used by the build method of the State. Fields in a Widget subclass are
  // always marked "final".

  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  int _counter = 0;

  void _incrementCounter() {
    setState(() {
      // This call to setState tells the Flutter framework that something has
      // changed in this State, which causes it to rerun the build method below
      // so that the display can reflect the updated values. If we changed
      // _counter without calling setState(), then the build method would not be
      // called again, and so nothing would appear to happen.
      _counter++;
    });
  }

  @override
  Widget build(BuildContext context) {
    // This method is rerun every time setState is called, for instance as done
    // by the _incrementCounter method above.
    //
    // The Flutter framework has been optimized to make rerunning build methods
    // fast, so that you can just rebuild anything that needs updating rather
    // than having to individually change instances of widgets.
    return Scaffold(
      appBar: AppBar(
        // TRY THIS: Try changing the color here to a specific color (to
        // AppColors.warning, perhaps?) and trigger a hot reload to see the AppBar
        // change color while the other colors stay the same.
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        // Here we take the value from the MyHomePage object that was created by
        // the App.build method, and use it to set our appbar title.
        title: Text(widget.title),
      ),
      body: Center(
        // Center is a layout widget. It takes a single child and positions it
        // in the middle of the parent.
        child: Column(
          // Column is also a layout widget. It takes a list of children and
          // arranges them vertically. By default, it sizes itself to fit its
          // children horizontally, and tries to be as tall as its parent.
          //
          // Column has various properties to control how it sizes itself and
          // how it positions its children. Here we use mainAxisAlignment to
          // center the children vertically; the main axis here is the vertical
          // axis because Columns are vertical (the cross axis would be
          // horizontal).
          //
          // TRY THIS: Invoke "debug painting" (choose the "Toggle Debug Paint"
          // action in the IDE, or press "p" in the console), to see the
          // wireframe for each widget.
          mainAxisAlignment: .center,
          children: [
            const Text('You have pushed the button this many times:'),
            Text(
              '$_counter',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _incrementCounter,
        tooltip: 'Increment',
        child: const Icon(Icons.add),
      ),
    );
  }
}
