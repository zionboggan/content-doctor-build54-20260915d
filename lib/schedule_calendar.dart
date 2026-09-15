// A compact calendar for filtering the durable schedule by Phoenix wall day.
// Dates arrive already expressed in that wall clock; this widget never shifts
// them through the device timezone.

import 'package:flutter/cupertino.dart';

import 'app_motion.dart';
import 'app_theme.dart';
import 'console_shell.dart';

class CdScheduleCalendar extends StatefulWidget {
  const CdScheduleCalendar({
    super.key,
    required this.scheduledDays,
    required this.selectedDay,
    required this.onSelected,
    this.today,
  });

  /// Phoenix wall dates supplied by the schedule screen. Multiple reels on a
  /// date intentionally still produce one dot: this is a day filter, not a
  /// made-up capacity meter.
  final List<DateTime> scheduledDays;
  final DateTime? selectedDay;
  final ValueChanged<DateTime?> onSelected;

  /// The caller owns the Phoenix wall clock. Supplying it avoids a device
  /// timezone conversion inside this presentation-only widget.
  final DateTime? today;

  @override
  State<CdScheduleCalendar> createState() => _CdScheduleCalendarState();
}

class _CdScheduleCalendarState extends State<CdScheduleCalendar> {
  late DateTime _month;

  @override
  void initState() {
    super.initState();
    _month = _initialMonth();
  }

  @override
  void didUpdateWidget(CdScheduleCalendar oldWidget) {
    super.didUpdateWidget(oldWidget);
    final DateTime? oldSelected = oldWidget.selectedDay;
    final DateTime? nextSelected = widget.selectedDay;
    if (!_sameDay(oldSelected, nextSelected) && nextSelected != null) {
      final DateTime selectedMonth = _monthStart(nextSelected);
      if (!_sameMonth(_month, selectedMonth)) _month = selectedMonth;
    }
  }

  DateTime _initialMonth() {
    return _monthStart(widget.selectedDay ?? widget.today ?? DateTime.now());
  }

  void _moveMonth(int offset) {
    setState(() => _month = DateTime(_month.year, _month.month + offset));
  }

  @override
  Widget build(BuildContext context) {
    final Set<int> scheduled = widget.scheduledDays.map<int>(_dayKey).toSet();
    final DateTime today = _dateOnly(widget.today ?? DateTime.now());
    final String title = _monthTitle(_month);
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 400),
      child: Container(
        decoration: BoxDecoration(
          color: Con.surface2,
          border: Border.all(color: Con.rule, width: SandBorder.hairline),
          borderRadius: BorderRadius.circular(SandRadius.r3),
        ),
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Row(
              children: <Widget>[
                _MonthButton(
                  label: 'Previous month',
                  icon: CupertinoIcons.chevron_left,
                  onPressed: () => _moveMonth(-1),
                ),
                Expanded(
                  child: Semantics(
                    header: true,
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: Ty.title.copyWith(color: Con.ink),
                    ),
                  ),
                ),
                _MonthButton(
                  label: 'Next month',
                  icon: CupertinoIcons.chevron_right,
                  onPressed: () => _moveMonth(1),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const _WeekdayLabels(),
            const SizedBox(height: 4),
            AnimatedSwitcher(
              duration: CdMotion.duration(context, CdMotion.screen),
              switchInCurve: CdMotion.out,
              switchOutCurve: CdMotion.into,
              transitionBuilder: (Widget child, Animation<double> animation) =>
                  FadeTransition(
                    opacity: animation,
                    child: SlideTransition(
                      position:
                          Tween<Offset>(
                                begin: const Offset(.025, 0),
                                end: Offset.zero,
                              )
                              .chain(CurveTween(curve: CdMotion.out))
                              .animate(animation),
                      child: child,
                    ),
                  ),
              child: _MonthGrid(
                key: ValueKey<String>('${_month.year}-${_month.month}'),
                month: _month,
                today: today,
                scheduled: scheduled,
                selected: widget.selectedDay,
                onSelected: widget.onSelected,
              ),
            ),
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerRight,
              child: CupertinoButton(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                minimumSize: const Size(32, 32),
                onPressed: widget.selectedDay == null
                    ? null
                    : () => widget.onSelected(null),
                child: const Text('All dates'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MonthButton extends StatelessWidget {
  const _MonthButton({
    required this.label,
    required this.icon,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: label,
    child: CupertinoButton(
      padding: EdgeInsets.zero,
      minimumSize: const Size(36, 36),
      onPressed: onPressed,
      child: Icon(icon, size: 16, color: Con.ink2),
    ),
  );
}

class _WeekdayLabels extends StatelessWidget {
  const _WeekdayLabels();

  static const List<String> _days = <String>['M', 'T', 'W', 'T', 'F', 'S', 'S'];

  @override
  Widget build(BuildContext context) => Row(
    children: <Widget>[
      for (final String day in _days)
        Expanded(
          child: Text(
            day,
            textAlign: TextAlign.center,
            style: Ty.caps.copyWith(color: Con.ink3, fontSize: 9),
          ),
        ),
    ],
  );
}

class _MonthGrid extends StatelessWidget {
  const _MonthGrid({
    super.key,
    required this.month,
    required this.today,
    required this.scheduled,
    required this.selected,
    required this.onSelected,
  });

  final DateTime month;
  final DateTime today;
  final Set<int> scheduled;
  final DateTime? selected;
  final ValueChanged<DateTime?> onSelected;

  @override
  Widget build(BuildContext context) {
    final DateTime first = _monthStart(month);
    final int leading = first.weekday - DateTime.monday;
    final int days = DateTime(month.year, month.month + 1, 0).day;
    final int cells = ((leading + days + 6) ~/ 7) * 7;
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 7,
        childAspectRatio: 1,
      ),
      itemCount: cells,
      itemBuilder: (BuildContext context, int index) {
        final int day = index - leading + 1;
        if (day < 1 || day > days) return const SizedBox.shrink();
        final DateTime date = DateTime(month.year, month.month, day);
        return _DayCell(
          date: date,
          isToday: _sameDay(today, date),
          isScheduled: scheduled.contains(_dayKey(date)),
          isSelected: _sameDay(selected, date),
          onTap: () => onSelected(_sameDay(selected, date) ? null : date),
        );
      },
    );
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.date,
    required this.isToday,
    required this.isScheduled,
    required this.isSelected,
    required this.onTap,
  });

  final DateTime date;
  final bool isToday;
  final bool isScheduled;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final Color tone = isSelected ? Con.onSignal : Con.ink2;
    final String label =
        '${_weekdayName(date.weekday)}, ${_monthName(date.month)} '
        '${date.day}, ${date.year}'
        '${isScheduled ? ', scheduled' : ''}'
        '${isToday ? ', today' : ''}'
        '${isSelected ? ', selected' : ''}';
    return Semantics(
      button: true,
      selected: isSelected,
      label: label,
      onTap: onTap,
      child: ExcludeSemantics(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: AnimatedScale(
            scale: isSelected && !CdMotion.reduced(context) ? 1.08 : 1,
            duration: CdMotion.duration(context, CdMotion.std),
            curve: CdMotion.spring,
            child: AnimatedContainer(
              duration: CdMotion.duration(context, CdMotion.std),
              curve: CdMotion.out,
              margin: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                color: isSelected ? Con.signal : const Color(0x00000000),
                border: Border.all(
                  color: isSelected
                      ? Con.signal
                      : isToday
                      ? Con.signalBright
                      : const Color(0x00000000),
                  width: isToday && !isSelected
                      ? SandBorder.interactive
                      : SandBorder.hairline,
                ),
                borderRadius: BorderRadius.circular(SandRadius.r1),
              ),
              child: Stack(
                alignment: Alignment.center,
                children: <Widget>[
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      '${date.day}',
                      style: Ty.meta.copyWith(
                        color: tone,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  if (isScheduled)
                    Positioned(
                      bottom: 3,
                      child: AnimatedContainer(
                        duration: CdMotion.duration(context, CdMotion.std),
                        curve: CdMotion.out,
                        width: 4,
                        height: 4,
                        decoration: BoxDecoration(
                          color: isSelected ? Con.onSignal : Con.holdBright,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

DateTime _dateOnly(DateTime value) =>
    DateTime(value.year, value.month, value.day);

DateTime _monthStart(DateTime value) => DateTime(value.year, value.month);

bool _sameDay(DateTime? a, DateTime? b) =>
    a != null &&
    b != null &&
    a.year == b.year &&
    a.month == b.month &&
    a.day == b.day;

bool _sameMonth(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month;

int _dayKey(DateTime date) =>
    (date.year * 10000) + (date.month * 100) + date.day;

const List<String> _months = <String>[
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];

const List<String> _weekdays = <String>[
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday',
];

String _monthTitle(DateTime date) => '${_months[date.month - 1]} ${date.year}';

String _monthName(int month) => _months[month - 1];

String _weekdayName(int weekday) => _weekdays[weekday - 1];
