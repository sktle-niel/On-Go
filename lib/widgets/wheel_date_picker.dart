import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_theme.dart';

/// Asks for a date with three spinning wheels — month, day, year — in a dialog.
///
/// The spinner layout Android users know from "Set date": each wheel shows the
/// value either side of the selection, the selection sits between two rules,
/// and CANCEL / SET close it. Month and day wheels wrap around (December
/// continues into January, the 31st into the 1st); the year wheel does not.
///
/// A drop-in for [showDatePicker]: it returns the chosen date, or null when the
/// dialog is cancelled or dismissed. Colours, corner shape and type all come
/// from the app theme, so it follows whichever theme the user has picked.
///
/// Nothing outside [firstDate]–[lastDate] can be chosen. The wheels only offer
/// months and days that exist inside the range for the year on screen, and an
/// [initialDate] outside it opens on the nearest end instead.
Future<DateTime?> showWheelDatePicker({
  required BuildContext context,
  required DateTime initialDate,
  required DateTime firstDate,
  required DateTime lastDate,
  String title = 'Set date',
  String cancelLabel = 'CANCEL',
  String confirmLabel = 'SET',
}) {
  assert(
    !DateUtils.dateOnly(lastDate).isBefore(DateUtils.dateOnly(firstDate)),
    'lastDate must not be before firstDate',
  );
  return showDialog<DateTime>(
    context: context,
    builder: (_) => WheelDatePickerDialog(
      initialDate: initialDate,
      firstDate: firstDate,
      lastDate: lastDate,
      title: title,
      cancelLabel: cancelLabel,
      confirmLabel: confirmLabel,
    ),
  );
}

const List<String> _monthAbbreviations = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

const List<String> _monthNames = [
  'January', 'February', 'March', 'April', 'May', 'June',
  'July', 'August', 'September', 'October', 'November', 'December',
];

/// The dialog [showWheelDatePicker] opens. Public so it can be embedded or
/// tested directly; most callers want the function.
class WheelDatePickerDialog extends StatefulWidget {
  const WheelDatePickerDialog({
    super.key,
    required this.initialDate,
    required this.firstDate,
    required this.lastDate,
    this.title = 'Set date',
    this.cancelLabel = 'CANCEL',
    this.confirmLabel = 'SET',
  });

  final DateTime initialDate;
  final DateTime firstDate;
  final DateTime lastDate;
  final String title;
  final String cancelLabel;
  final String confirmLabel;

  @override
  State<WheelDatePickerDialog> createState() => _WheelDatePickerDialogState();
}

class _WheelDatePickerDialogState extends State<WheelDatePickerDialog> {
  late DateTime _first;
  late DateTime _last;

  // The date on screen. The wheels are views of these three numbers, never the
  // other way round — a wheel's scroll position is turned into a value here,
  // and when a value has to change for another reason (February has no 31st)
  // the wheel is moved to match.
  late int _year;
  late int _month;
  late int _day;

  late final FixedExtentScrollController _yearCtrl;
  late final FixedExtentScrollController _monthCtrl;
  late final FixedExtentScrollController _dayCtrl;

  /// Set while this state is moving a wheel itself, so the wheel reporting
  /// that move is not mistaken for the user choosing something.
  bool _realigning = false;

  @override
  void initState() {
    super.initState();
    _first = DateUtils.dateOnly(widget.firstDate);
    _last = DateUtils.dateOnly(widget.lastDate);

    var start = DateUtils.dateOnly(widget.initialDate);
    if (start.isBefore(_first)) start = _first;
    if (start.isAfter(_last)) start = _last;
    _year = start.year;
    _month = start.month;
    _day = start.day;

    _yearCtrl = FixedExtentScrollController(initialItem: _year - _first.year);
    _monthCtrl = FixedExtentScrollController(initialItem: _month - _minMonth);
    _dayCtrl = FixedExtentScrollController(initialItem: _day - _minDay);
  }

  @override
  void dispose() {
    _yearCtrl.dispose();
    _monthCtrl.dispose();
    _dayCtrl.dispose();
    super.dispose();
  }

  // ------------------------------------------------------------ the ranges ---
  // What each wheel may offer, for the year and month currently on screen.
  // Only the first and last years of the range are ever cut short.

  int get _minMonth => _year == _first.year ? _first.month : 1;
  int get _maxMonth => _year == _last.year ? _last.month : 12;

  int get _minDay => _year == _first.year && _month == _first.month ? _first.day : 1;

  int get _maxDay {
    final days = DateUtils.getDaysInMonth(_year, _month);
    return _year == _last.year && _month == _last.month ? math.min(days, _last.day) : days;
  }

  /// A wheel wraps only when it has at least as many values as rows on show.
  /// Fewer, and wrapping would show the same value twice at once.
  static bool _loops(int min, int max) => max - min + 1 >= _visibleRows;

  static const int _visibleRows = 3;

  /// The value at wheel position [index] for a wheel offering [min]–[max].
  /// A wrapping wheel's positions run on forever in both directions.
  static int _valueAt(int index, int min, int max) {
    final count = max - min + 1;
    return _loops(min, max) ? min + index % count : min + index.clamp(0, count - 1);
  }

  // -------------------------------------------------- the user moves a wheel ---

  void _onYearIndex(int index) {
    if (_realigning) return;
    final year = _first.year + index.clamp(0, _last.year - _first.year);
    if (year == _year) return;
    setState(() {
      _year = year;
      // A year at either end of the range may not have this month or day.
      _month = _month.clamp(_minMonth, _maxMonth);
      _day = _day.clamp(_minDay, _maxDay);
    });
    _realign(_monthCtrl, () => (_month, _minMonth, _maxMonth));
    _realign(_dayCtrl, () => (_day, _minDay, _maxDay));
    HapticFeedback.selectionClick();
  }

  void _onMonthIndex(int index) {
    if (_realigning) return;
    final month = _valueAt(index, _minMonth, _maxMonth);
    if (month == _month) return;
    setState(() {
      _month = month;
      // The 31st does not survive a move to a 30-day month, nor the 29th a
      // move to February outside a leap year.
      _day = _day.clamp(_minDay, _maxDay);
    });
    _realign(_dayCtrl, () => (_day, _minDay, _maxDay));
    HapticFeedback.selectionClick();
  }

  void _onDayIndex(int index) {
    if (_realigning) return;
    final day = _valueAt(index, _minDay, _maxDay);
    if (day == _day) return;
    setState(() => _day = day);
    HapticFeedback.selectionClick();
  }

  /// Moves a wheel so it shows the value state says it should.
  ///
  /// Needed whenever a wheel's range changes under it. A wrapping day wheel
  /// sitting at position 40 shows the 10th of a 31-day month but the 13th of a
  /// 28-day one, so a month change has to move it back onto the 10th — to the
  /// nearest position that shows it, so nothing visibly jumps.
  ///
  /// [target] is read when it is used rather than when this is called, because
  /// the check runs again after the next frame, by which time the wheel has
  /// been rebuilt with its new range.
  void _realign(
    FixedExtentScrollController ctrl,
    (int value, int min, int max) Function() target,
  ) {
    void align() {
      if (!mounted || !ctrl.hasClients) return;
      final (value, min, max) = target();
      final current = ctrl.selectedItem;
      if (_valueAt(current, min, max) == value) return;
      final count = max - min + 1;
      final index = _loops(min, max) ? current - current % count + (value - min) : value - min;
      _realigning = true;
      ctrl.jumpToItem(index);
      _realigning = false;
    }

    align();
    WidgetsBinding.instance.addPostFrameCallback((_) => align());
  }

  /// Steps a wheel [delta] rows — a tap on a neighbouring row, or a screen
  /// reader's increase / decrease.
  void _step(FixedExtentScrollController ctrl, int delta, {required bool loops, required int count}) {
    if (!ctrl.hasClients || delta == 0) return;
    var index = ctrl.selectedItem + delta;
    if (!loops) index = index.clamp(0, count - 1);
    ctrl.animateToItem(index, duration: const Duration(milliseconds: 220), curve: Curves.easeOutCubic);
  }

  // ---------------------------------------------------------------- layout ---

  @override
  Widget build(BuildContext context) {
    final layout = context.layout;
    final theme = Theme.of(context);

    // Row pitch. 64 scaled from the 390-point baseline comes to ~59 points on
    // a 360-point phone — the reference screenshot's own width, where its rows
    // sit 60 apart and its rules 50 — and grows a little on bigger screens.
    //
    // Two limits on top. A short window, such as a phone on its side, cannot
    // give each row 13% of its height without the dialog outgrowing the
    // screen, so rows give way there. And whatever else happens, a row stays
    // at least 2.6 lines of text tall, so a reader's enlarged numbers never
    // touch the rules either side of them.
    final textHeight = MediaQuery.textScalerOf(context).scale(16);
    final itemExtent = math.max(
      math.min(layout.scale(64, max: 1.15), layout.height * 0.13),
      textHeight * 2.6,
    );

    final monthLoops = _loops(_minMonth, _maxMonth);
    final dayLoops = _loops(_minDay, _maxDay);
    final monthCount = _maxMonth - _minMonth + 1;
    final dayCount = _maxDay - _minDay + 1;
    final yearCount = _last.year - _first.year + 1;

    final buttonStyle = TextButton.styleFrom(
      foregroundColor: AppColors.textdark,
      textStyle: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600, letterSpacing: 0.6),
    );

    return Dialog(
      insetPadding: EdgeInsets.symmetric(horizontal: layout.gutter, vertical: 24),
      child: ConstrainedBox(
        // Roughly a phone's reference width, a little wider on a tablet — the
        // wheels are for picking, and stretching them across a tablet only
        // puts the columns further from each other.
        constraints: BoxConstraints(maxWidth: layout.scale(300, max: 1.2)),
        child: SingleChildScrollView(
          // A phone on its side at the largest text size is the one case where
          // this does not fit; it scrolls there instead of overflowing.
          physics: const ClampingScrollPhysics(),
          child: Padding(
            padding: const EdgeInsets.only(top: 24, bottom: 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Text(
                    widget.title,
                    style: theme.textTheme.titleLarge?.copyWith(
                      color: AppColors.textdark,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: _Wheel(
                          key: const ValueKey('wheel-month'),
                          controller: _monthCtrl,
                          itemExtent: itemExtent,
                          loops: monthLoops,
                          selected: _month - _minMonth,
                          labels: [for (var m = _minMonth; m <= _maxMonth; m++) _monthAbbreviations[m - 1]],
                          semanticsLabel: 'Month',
                          semanticValues: [for (var m = _minMonth; m <= _maxMonth; m++) _monthNames[m - 1]],
                          onIndexChanged: _onMonthIndex,
                          onStep: (d) => _step(_monthCtrl, d, loops: monthLoops, count: monthCount),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: _Wheel(
                          key: const ValueKey('wheel-day'),
                          controller: _dayCtrl,
                          itemExtent: itemExtent,
                          loops: dayLoops,
                          selected: _day - _minDay,
                          labels: [for (var d = _minDay; d <= _maxDay; d++) d.toString().padLeft(2, '0')],
                          semanticsLabel: 'Day',
                          semanticValues: [for (var d = _minDay; d <= _maxDay; d++) '$d'],
                          onIndexChanged: _onDayIndex,
                          onStep: (d) => _step(_dayCtrl, d, loops: dayLoops, count: dayCount),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: _Wheel(
                          key: const ValueKey('wheel-year'),
                          controller: _yearCtrl,
                          itemExtent: itemExtent,
                          loops: false,
                          selected: _year - _first.year,
                          labels: [for (var y = _first.year; y <= _last.year; y++) '$y'],
                          semanticsLabel: 'Year',
                          semanticValues: [for (var y = _first.year; y <= _last.year; y++) '$y'],
                          onIndexChanged: _onYearIndex,
                          onStep: (d) => _step(_yearCtrl, d, loops: false, count: yearCount),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  // OverflowBar, as AlertDialog uses: side by side at the right
                  // when they fit, stacked when a large text size means they
                  // do not.
                  child: OverflowBar(
                    alignment: MainAxisAlignment.end,
                    spacing: 8,
                    children: [
                      TextButton(
                        style: buttonStyle,
                        onPressed: () => Navigator.pop(context),
                        child: Text(widget.cancelLabel),
                      ),
                      TextButton(
                        style: buttonStyle,
                        onPressed: () => Navigator.pop(context, DateTime(_year, _month, _day)),
                        child: Text(widget.confirmLabel),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// One spinning column: three rows on show, the middle one selected and held
/// between two rules, the rows either side dimmed.
class _Wheel extends StatelessWidget {
  const _Wheel({
    super.key,
    required this.controller,
    required this.itemExtent,
    required this.loops,
    required this.selected,
    required this.labels,
    required this.semanticsLabel,
    required this.semanticValues,
    required this.onIndexChanged,
    required this.onStep,
  });

  final FixedExtentScrollController controller;
  final double itemExtent;
  final bool loops;

  /// Offset of the selected value within [labels].
  final int selected;

  /// What each row shows, in order.
  final List<String> labels;

  /// What a screen reader calls this wheel, and each value in full — "March"
  /// rather than "Mar", "1" rather than "01".
  final String semanticsLabel;
  final List<String> semanticValues;

  final ValueChanged<int> onIndexChanged;

  /// Moves the wheel by a number of rows.
  final ValueChanged<int> onStep;

  @override
  Widget build(BuildContext context) {
    final base = Theme.of(context).textTheme.titleMedium ?? const TextStyle(fontSize: 15);
    final count = labels.length;

    Widget row(int i) {
      final isSelected = i == selected;
      return Center(
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            labels[i],
            maxLines: 1,
            style: base.copyWith(
              color: isSelected ? AppColors.textdark : AppColors.textdark.withValues(alpha: 0.45),
              fontWeight: isSelected ? FontWeight.w700 : FontWeight.w400,
            ),
          ),
        ),
      );
    }

    final rows = [for (var i = 0; i < count; i++) row(i)];
    final rule = Container(height: AppBorders.regular, color: AppColors.textmedium);

    final canIncrease = loops || selected < count - 1;
    final canDecrease = loops || selected > 0;

    return Semantics(
      container: true,
      label: semanticsLabel,
      value: semanticValues[selected],
      increasedValue: canIncrease ? semanticValues[(selected + 1) % count] : null,
      decreasedValue: canDecrease ? semanticValues[(selected - 1) % count] : null,
      onIncrease: canIncrease ? () => onStep(1) : null,
      onDecrease: canDecrease ? () => onStep(-1) : null,
      child: ExcludeSemantics(
        child: SizedBox(
          height: itemExtent * _WheelDatePickerDialogState._visibleRows,
          child: Stack(
            children: [
              ListWheelScrollView.useDelegate(
                controller: controller,
                itemExtent: itemExtent,
                physics: const FixedExtentScrollPhysics(),
                // Flat, as in the reference: a very large diameter and almost
                // no perspective leave the rows as a straight column rather
                // than a drum.
                diameterRatio: 1000,
                perspective: 0.0001,
                onSelectedItemChanged: onIndexChanged,
                childDelegate: loops
                    ? ListWheelChildLoopingListDelegate(children: rows)
                    : ListWheelChildListDelegate(children: rows),
              ),
              // The two rules marking the selection. Slightly shorter than a
              // row, so there is air between the rules and the rows either
              // side.
              IgnorePointer(
                child: Center(
                  child: SizedBox(
                    height: itemExtent * 0.84,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [rule, rule],
                    ),
                  ),
                ),
              ),
              // Tapping the row above or below steps to it. Translucent, so the
              // wheel beneath still receives drags and flings.
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onTapUp: (details) {
                    final row = (details.localPosition.dy / itemExtent).floor() - 1;
                    if (row != 0) onStep(row.clamp(-1, 1));
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
