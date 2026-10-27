import 'package:flutter/material.dart';

import '../database/database_helper.dart';
import '../models/task_model.dart';
import '../services/auth_service.dart';
import '../services/notification_service.dart';
import '../services/shared_pref_service.dart';
import '../services/smart_parser.dart';
import '../services/task_breakdown.dart';
import '../services/task_events.dart';
import '../services/task_intelligence.dart';
import '../services/voice_input.dart';
import '../utils/app_colors.dart';
import '../utils/app_spacing.dart';
import '../utils/constants.dart';
import '../utils/date_helper.dart';
import 'add_task_screen.dart';
import 'plan_day_sheet.dart';

/// The assistant behind the + button.
///
/// Type a task the way you would say it; the sheet parses it, fills in
/// anything you left out from what it has learned about you, and can split a
/// big task into steps. Everything happens on the device — there is no model
/// call and no network.
class AiAssistSheet extends StatefulWidget {
  const AiAssistSheet({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const AiAssistSheet(),
    );
  }

  @override
  State<AiAssistSheet> createState() => _AiAssistSheetState();
}

class _AiAssistSheetState extends State<AiAssistSheet> {
  final _controller = TextEditingController();
  final _focus = FocusNode();

  TaskProfile _profile = const TaskProfile();
  ParsedTask? _parsed;
  Breakdown? _breakdown;
  Set<int> _chosenSteps = {};
  bool _saving = false;

  bool _listening = false;
  bool _voiceAvailable = false;
  String _voiceLocale = VoiceInput.defaultLocale;

  @override
  void initState() {
    super.initState();
    _loadProfile();
    _prepareVoice();
  }

  Future<void> _loadProfile() async {
    final profile = await TaskIntelligence.learn(AuthService.uid);
    if (!mounted) return;
    setState(() => _profile = profile);
  }

  Future<void> _prepareVoice() async {
    final locale = await SharedPrefService.getVoiceLocale();
    // Does not prompt for the microphone — that happens on the first tap.
    final available = await VoiceInput.init();

    if (!mounted) return;
    setState(() {
      _voiceLocale = locale;
      _voiceAvailable = available;
    });
  }

  @override
  void dispose() {
    VoiceInput.cancel();
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  // ===========================
  // DERIVED VALUES
  // ===========================

  String get _title => (_parsed?.title ?? _controller.text).trim();

  String get _category =>
      _parsed?.category ?? AppConstants.categoryNames.first;

  /// The parser wins; anything it did not find falls back to what the profile
  /// learned, and only then to a plain default.
  Suggestion<TimeOfDay>? get _learnedTime =>
      _parsed?.time != null ? null : _profile.suggestTime(_category);

  Suggestion<String>? get _learnedPriority =>
      _parsed?.priority != null ? null : _profile.suggestPriority(_category);

  TimeOfDay get _effectiveTime =>
      _parsed?.time ?? _learnedTime?.value ?? const TimeOfDay(hour: 9, minute: 0);

  DateTime get _effectiveDate =>
      _parsed?.date ?? DateHelper.dateOnly(DateTime.now());

  String get _effectivePriority =>
      _parsed?.priority ??
      _learnedPriority?.value ??
      AppConstants.priorityMedium;

  // ===========================
  // ACTIONS
  // ===========================

  void _onChanged(String value) {
    setState(() {
      _parsed = value.trim().isEmpty ? null : SmartTaskParser.parse(value);
      // The old breakdown belongs to the old title.
      _breakdown = null;
      _chosenSteps = {};
    });
  }

  Future<void> _toggleVoice() async {
    if (_listening) {
      await VoiceInput.stop();
      if (mounted) setState(() => _listening = false);
      return;
    }

    FocusScope.of(context).unfocus();

    final started = await VoiceInput.start(
      localeId: _voiceLocale,
      onResult: (text, isFinal) {
        if (!mounted) return;

        _controller.text = text;
        _controller.selection =
            TextSelection.collapsed(offset: text.length);
        _onChanged(text);

        if (isFinal) setState(() => _listening = false);
      },
      onError: (message) {
        if (!mounted) return;
        setState(() => _listening = false);
        _toast('Could not hear that', detail: message);
      },
    );

    if (!mounted) return;

    if (!started) {
      _toast(
        'Voice input is not available',
        detail: 'Allow the microphone, or check that your phone has a '
            'speech recogniser installed.',
      );
      return;
    }

    setState(() => _listening = true);
  }

  void _useFrequent(FrequentTask task) {
    _controller.text = task.title;
    _onChanged(task.title);
    _focus.requestFocus();
  }

  void _splitIntoSteps() {
    if (_title.isEmpty) return;

    final breakdown = TaskBreakdown.suggest(_title);
    setState(() {
      _breakdown = breakdown;
      _chosenSteps = {for (var i = 0; i < breakdown.steps.length; i++) i};
    });
  }

  Future<TaskModel> _buildAndSave({
    required String title,
    String description = '',
    TimeOfDay? time,
  }) async {
    final task = TaskModel(
      userId: AuthService.uid,
      title: title,
      description: description,
      category: _category,
      priority: _effectivePriority,
      date: DateHelper.toIsoDate(_effectiveDate),
      time: DateHelper.toStoredTime(time ?? _effectiveTime),
      reminder: true,
    );

    task.id = await DatabaseHelper.instance.insertTask(task);
    await NotificationService.scheduleForTask(task);
    return task;
  }

  Future<void> _addTask() async {
    if (_title.isEmpty || AuthService.uid.isEmpty) return;

    setState(() => _saving = true);

    try {
      await _buildAndSave(title: _title);
      notifyTasksChanged();

      if (!mounted) return;
      Navigator.pop(context);
      _toast('Task added',
          detail: '${DateHelper.relativeLabel(_effectiveDate)} • '
              '${DateHelper.prettyTime(_effectiveTime)}');
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      _toast('Could not add the task: $error');
    }
  }

  /// Steps become separate tasks — the app has no sub-task type, and the sheet
  /// says so rather than quietly flattening them.
  Future<void> _addSteps() async {
    final breakdown = _breakdown;
    if (breakdown == null || _chosenSteps.isEmpty) return;

    setState(() => _saving = true);

    try {
      // Space the steps through the day so they do not all alarm at once.
      var minutes = _effectiveTime.hour * 60 + _effectiveTime.minute;

      final chosen = _chosenSteps.toList()..sort();
      for (final index in chosen) {
        await _buildAndSave(
          title: breakdown.steps[index],
          description: 'Part of: $_title',
          time: TimeOfDay(
            hour: (minutes ~/ 60).clamp(0, 23),
            minute: minutes % 60,
          ),
        );
        minutes += 60;
      }

      notifyTasksChanged();

      if (!mounted) return;
      Navigator.pop(context);
      _toast('${chosen.length} steps added',
          detail: 'Each one is its own task under $_category');
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      _toast('Could not add the steps: $error');
    }
  }

  Future<void> _openFullForm() async {
    Navigator.pop(context);
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AddTaskScreen(initialDate: _effectiveDate),
      ),
    );
  }

  void _toast(String message, {String? detail}) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger
      ?..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(message),
              if (detail != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    detail,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 13,
                    ),
                  ),
                ),
            ],
          ),
        ),
      );
  }

  // ===========================
  // UI
  // ===========================

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: DraggableScrollableSheet(
        initialChildSize: 0.72,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, scrollController) {
          return Container(
            decoration: BoxDecoration(
              color: const Color(0xFF10162F),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(AppSpacing.radiusSheet),
              ),
              border: Border.all(
                color: AppColors.purple.withValues(alpha: .35),
              ),
              boxShadow: [
                BoxShadow(
                  color: AppColors.purple.withValues(alpha: .25),
                  blurRadius: 40,
                ),
              ],
            ),
            child: ListView(
              controller: scrollController,
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.page,
                AppSpacing.sm,
                AppSpacing.page,
                AppSpacing.xl,
              ),
              children: [
                _grabber(),
                const SizedBox(height: AppSpacing.md),
                _header(),
                const SizedBox(height: AppSpacing.lg),
                _input(),
                const SizedBox(height: AppSpacing.md),
                if (_parsed != null) ..._readingBack(),
                if (_parsed == null) ..._emptyStateSuggestions(),
                if (_breakdown != null) ..._stepsSection(),
                const SizedBox(height: AppSpacing.lg),
                _actions(),
                const SizedBox(height: AppSpacing.md),
                _footer(),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _grabber() {
    return Center(
      child: Container(
        width: 42,
        height: 4,
        decoration: BoxDecoration(
          color: Colors.white24,
          borderRadius: BorderRadius.circular(4),
        ),
      ),
    );
  }

  Widget _header() {
    return Row(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            gradient: AppColors.primaryGradient,
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Icon(
            Icons.auto_awesome_rounded,
            color: Colors.white,
            size: AppSpacing.iconFeature,
          ),
        ),
        const SizedBox(width: AppSpacing.sm + 2),
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'AI Assist',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 19,
                  fontWeight: FontWeight.bold,
                ),
              ),
              SizedBox(height: 2),
              Text(
                'Runs on this phone — nothing is sent anywhere',
                style: TextStyle(color: Colors.white54, fontSize: 12.5),
              ),
            ],
          ),
        ),
        IconButton(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.close_rounded, color: Colors.white54),
        ),
      ],
    );
  }

  Widget _input() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _controller,
          focusNode: _focus,
          autofocus: true,
          maxLines: 3,
          minLines: 1,
          textCapitalization: TextCapitalization.sentences,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 16,
            height: 1.4,
          ),
          onChanged: _onChanged,
          decoration: InputDecoration(
            hintText: 'Submit the client report tomorrow 5pm urgent',
            hintStyle: const TextStyle(color: Colors.white38, fontSize: 15),
            filled: true,
            fillColor: Colors.white.withValues(alpha: .06),
            contentPadding: const EdgeInsets.all(AppSpacing.md),
            suffixIcon: _voiceAvailable
                ? IconButton(
                    onPressed: _saving ? null : _toggleVoice,
                    tooltip: _listening ? 'Stop' : 'Speak instead',
                    icon: Icon(
                      _listening ? Icons.stop_rounded : Icons.mic_none_rounded,
                      color: _listening ? AppColors.pink : Colors.white70,
                    ),
                  )
                : null,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppSpacing.radiusField),
              borderSide: BorderSide.none,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppSpacing.radiusField),
              borderSide:
                  BorderSide(color: Colors.white.withValues(alpha: .10)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppSpacing.radiusField),
              borderSide: const BorderSide(
                color: AppColors.purple,
                width: 1.5,
              ),
            ),
          ),
        ),

        if (_listening) ...[
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation(AppColors.pink),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  'Listening — speak normally, Tanglish is fine',
                  style: TextStyle(
                    color: AppColors.pink.withValues(alpha: .9),
                    fontSize: 13,
                  ),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  /// What the app understood, stated plainly so a wrong guess is obvious.
  List<Widget> _readingBack() {
    final chips = <Widget>[
      _chip(Icons.title_rounded, _title.isEmpty ? 'No title yet' : _title),
      _chip(
        Icons.calendar_today_rounded,
        DateHelper.relativeLabel(_effectiveDate),
      ),
      _chip(Icons.schedule_rounded, DateHelper.prettyTime(_effectiveTime)),
      _chip(Icons.flag_rounded, _effectivePriority),
      _chip(AppConstants.categoryOf(_category).icon, _category),
    ];

    return [
      const _SectionLabel('Reading it as'),
      const SizedBox(height: AppSpacing.sm),
      Wrap(spacing: AppSpacing.sm, runSpacing: AppSpacing.sm, children: chips),
      if (_learnedTime != null || _learnedPriority != null) ...[
        const SizedBox(height: AppSpacing.md),
        _learnedNote(),
      ],
      const SizedBox(height: AppSpacing.md),
      TextButton.icon(
        onPressed: _title.isEmpty ? null : _splitIntoSteps,
        icon: const Icon(
          Icons.account_tree_outlined,
          size: AppSpacing.iconList,
          color: AppColors.blue,
        ),
        label: const Text(
          'Split into steps',
          style: TextStyle(
            color: AppColors.blue,
            fontWeight: FontWeight.w600,
          ),
        ),
        style: TextButton.styleFrom(padding: EdgeInsets.zero),
      ),
    ];
  }

  /// The "it remembers" part, shown with its reason.
  Widget _learnedNote() {
    final reasons = [
      if (_learnedTime != null) _learnedTime!.reason,
      if (_learnedPriority != null) _learnedPriority!.reason,
    ];

    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm + 2),
      decoration: BoxDecoration(
        color: AppColors.purple.withValues(alpha: .12),
        borderRadius: BorderRadius.circular(AppSpacing.radiusField),
        border: Border.all(color: AppColors.purple.withValues(alpha: .3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.psychology_outlined,
            size: AppSpacing.iconList,
            color: AppColors.purple,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Filled in from your habits',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                ...reasons.map(
                  (reason) => Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      reason,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 12.5,
                        height: 1.4,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _emptyStateSuggestions() {
    final frequent = _profile.suggestionsFor(DateTime.now());

    return [
      if (frequent.isNotEmpty) ...[
        const _SectionLabel('You add these often'),
        const SizedBox(height: AppSpacing.sm),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: frequent
              .map(
                (task) => ActionChip(
                  onPressed: () => _useFrequent(task),
                  backgroundColor: Colors.white.withValues(alpha: .07),
                  side: BorderSide(color: Colors.white.withValues(alpha: .12)),
                  avatar: Icon(
                    task.isRecurring
                        ? Icons.repeat_rounded
                        : Icons.history_rounded,
                    size: AppSpacing.iconChip + 2,
                    color: Colors.white70,
                  ),
                  label: Text(
                    task.title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13.5,
                    ),
                  ),
                ),
              )
              .toList(),
        ),
        const SizedBox(height: AppSpacing.md),
      ],
      _examples(),
    ];
  }

  Widget _examples() {
    const samples = [
      'Gym tomorrow 6am',
      'Pay rent on friday',
      'Buy groceries in 2 days',
    ];

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .04),
        borderRadius: BorderRadius.circular(AppSpacing.radiusField),
        border: Border.all(color: Colors.white.withValues(alpha: .08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Try writing it the way you would say it',
            style: TextStyle(
              color: Colors.white70,
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          ...samples.map(
            (sample) => Padding(
              padding: const EdgeInsets.only(top: 6),
              child: GestureDetector(
                onTap: () {
                  _controller.text = sample;
                  _onChanged(sample);
                },
                child: Text(
                  '“$sample”',
                  style: const TextStyle(
                    color: Colors.white54,
                    fontSize: 13.5,
                    height: 1.5,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _stepsSection() {
    final breakdown = _breakdown!;

    return [
      const SizedBox(height: AppSpacing.lg),
      const _SectionLabel('Suggested steps'),
      const SizedBox(height: 4),
      Text(
        breakdown.basis,
        style: const TextStyle(color: Colors.white54, fontSize: 12.5),
      ),
      const SizedBox(height: AppSpacing.sm),
      ...List.generate(breakdown.steps.length, (index) {
        final selected = _chosenSteps.contains(index);
        return CheckboxListTile(
          value: selected,
          onChanged: (value) => setState(() {
            if (value == true) {
              _chosenSteps.add(index);
            } else {
              _chosenSteps.remove(index);
            }
          }),
          dense: true,
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          activeColor: AppColors.pink,
          title: Text(
            breakdown.steps[index],
            style: TextStyle(
              color: selected ? Colors.white : Colors.white54,
              fontSize: 14.5,
            ),
          ),
        );
      }),
      const SizedBox(height: 4),
      const Text(
        'These are added as separate tasks — TaskFlow has no sub-tasks yet.',
        style: TextStyle(color: Colors.white38, fontSize: 12, height: 1.4),
      ),
    ];
  }

  Widget _actions() {
    final hasSteps = _breakdown != null && _chosenSteps.isNotEmpty;

    return Column(
      children: [
        SizedBox(
          width: double.infinity,
          height: 54,
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: AppColors.primaryGradient,
              borderRadius: BorderRadius.circular(AppSpacing.radiusField),
            ),
            child: ElevatedButton.icon(
              onPressed: _saving || _title.isEmpty
                  ? null
                  : (hasSteps ? _addSteps : _addTask),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.transparent,
                disabledBackgroundColor: Colors.transparent,
                shadowColor: Colors.transparent,
                shape: RoundedRectangleBorder(
                  borderRadius:
                      BorderRadius.circular(AppSpacing.radiusField),
                ),
              ),
              icon: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.2,
                        valueColor: AlwaysStoppedAnimation(Colors.white),
                      ),
                    )
                  : Icon(
                      hasSteps ? Icons.playlist_add_rounded : Icons.add_rounded,
                      color: Colors.white,
                    ),
              label: Text(
                hasSteps
                    ? 'Add ${_chosenSteps.length} steps'
                    : 'Add task',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Row(
          children: [
            Expanded(
              child: TextButton.icon(
                onPressed: _saving ? null : _openFullForm,
                icon: const Icon(
                  Icons.tune_rounded,
                  size: AppSpacing.iconList,
                  color: Colors.white70,
                ),
                label: const Text(
                  'More options',
                  style: TextStyle(color: Colors.white70),
                ),
              ),
            ),
            Expanded(
              child: TextButton.icon(
                onPressed: _saving
                    ? null
                    : () {
                        Navigator.pop(context);
                        PlanDaySheet.show(context);
                      },
                icon: const Icon(
                  Icons.event_note_rounded,
                  size: AppSpacing.iconList,
                  color: Colors.white70,
                ),
                label: const Text(
                  'Plan my day',
                  style: TextStyle(color: Colors.white70),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _footer() {
    final learned = _profile.hasLearnedEnough
        ? 'Learned from your ${_profile.totalTasks} tasks'
        : 'Add a few more tasks and it will start spotting your patterns';

    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.lock_outline_rounded,
              size: AppSpacing.iconChip,
              color: Colors.white30,
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                learned,
                style: const TextStyle(color: Colors.white30, fontSize: 12),
              ),
            ),
          ],
        ),

        // The one caveat to "nothing leaves the phone" — said out loud
        // rather than buried, because it is a real exception.
        if (_voiceAvailable) ...[
          const SizedBox(height: 6),
          const Text(
            'Voice uses your phone\'s own speech recogniser, which may use '
            'the internet. Everything else stays here.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white24,
              fontSize: 11.5,
              height: 1.4,
            ),
          ),
        ],
      ],
    );
  }

  Widget _chip(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm + 2,
        vertical: 7,
      ),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .07),
        borderRadius: BorderRadius.circular(AppSpacing.radiusChip),
        border: Border.all(color: Colors.white.withValues(alpha: .12)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: AppSpacing.iconChip, color: Colors.white54),
          const SizedBox(width: 6),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 200),
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;

  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: const TextStyle(
        color: Colors.white38,
        fontSize: 11.5,
        fontWeight: FontWeight.bold,
        letterSpacing: 1.1,
      ),
    );
  }
}
