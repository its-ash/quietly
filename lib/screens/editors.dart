import 'package:flutter/material.dart';
import 'package:theme/theme.dart';

import '../rules/kinds.dart';
import '../rules/needs.dart';
import '../rules/rule.dart';
import '../rules/rules_platform.dart';
import '../rules/rules_store.dart';
import '../widgets/need_notice.dart';

/// Bottom sheets that edit one condition or one action. Each returns the new
/// value, or null when the sheet is closed without saving.

Future<Condition?> editCondition(BuildContext context, RulesStore store, ConditionType type, [Condition? initial]) {
  switch (type) {
    case ConditionType.headphones:
      return Future.value(const HeadphonesCondition());
    case ConditionType.charging:
      return Future.value(const ChargingCondition());
    case ConditionType.wifi:
      return _sheet<Condition>(
        context,
        type.title,
        type.description,
        _WifiEditor(store: store, initial: initial is WifiCondition ? initial : null),
      );
    case ConditionType.time:
      return _sheet<Condition>(
        context,
        type.title,
        type.description,
        _TimeEditor(initial: initial is TimeCondition ? initial : null),
      );
    case ConditionType.bluetooth:
      return _sheet<Condition>(
        context,
        type.title,
        type.description,
        _BluetoothEditor(store: store, initial: initial is BluetoothCondition ? initial : null),
      );
    case ConditionType.battery:
      return _sheet<Condition>(
        context,
        type.title,
        type.description,
        _PercentEditor<Condition>(
          label: 'Battery below',
          initial: initial is BatteryCondition ? initial.below : 20,
          min: 5,
          max: 95,
          build: (p) => BatteryCondition(below: p),
        ),
      );
  }
}

Future<RuleAction?> editAction(BuildContext context, RulesStore store, ActionType type, [RuleAction? initial]) {
  final Widget editor = switch (type) {
    ActionType.ringer => _ChoiceEditor<Ringer>(
      store: store,
      options: [for (final r in Ringer.values) UiChoice(r, r.label)],
      initial: initial is RingerAction ? initial.mode : Ringer.vibrate,
      build: RingerAction.new,
      need: (mode) => mode == Ringer.silent ? Need.dnd : null,
    ),
    ActionType.dnd => _ChoiceEditor<bool>(
      store: store,
      options: const [UiChoice(true, 'Turn on'), UiChoice(false, 'Turn off')],
      initial: initial is DndAction ? initial.on : true,
      build: (on) => DndAction(on: on),
      need: (_) => Need.dnd,
    ),
    ActionType.mediaVolume => _PercentEditor<RuleAction>(
      label: 'Media volume',
      initial: initial is MediaVolumeAction ? initial.percent : 50,
      build: MediaVolumeAction.new,
    ),
    ActionType.ringVolume => _PercentEditor<RuleAction>(
      label: 'Ring volume',
      initial: initial is RingVolumeAction ? initial.percent : 50,
      build: RingVolumeAction.new,
    ),
    ActionType.brightness => _PercentEditor<RuleAction>(
      label: 'Brightness',
      initial: initial is BrightnessAction ? initial.percent : 50,
      min: 5,
      build: BrightnessAction.new,
      store: store,
      need: Need.writeSettings,
    ),
    ActionType.openApp => _AppEditor(store: store, initial: initial is OpenAppAction ? initial : null),
    ActionType.notify => _NotifyEditor(store: store, initial: initial is NotifyAction ? initial.text : ''),
  };
  return _sheet<RuleAction>(context, type.title, type.description, editor);
}

Future<T?> _sheet<T>(BuildContext context, String title, String subtitle, Widget child) =>
    UiSheet.show<T>(context, title: title, subtitle: subtitle, child: child);

/// The sheet body: the fields, then the Done button.
class _Form extends StatelessWidget {
  const _Form({required this.children, required this.onDone});

  final List<Widget> children;
  final VoidCallback? onDone;

  @override
  Widget build(BuildContext context) {
    return UiColumn(
      gap: UiSpace.lg,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ...children,
        UiButton('Done', expand: true, onPressed: onDone),
      ],
    );
  }
}

class _WifiEditor extends StatefulWidget {
  const _WifiEditor({required this.store, this.initial});

  final RulesStore store;
  final WifiCondition? initial;

  @override
  State<_WifiEditor> createState() => _WifiEditorState();
}

class _WifiEditorState extends State<_WifiEditor> {
  late final _name = TextEditingController(text: widget.initial?.ssid ?? '');
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _useCurrent() async {
    final platform = widget.store.platform;
    setState(() => _busy = true);
    try {
      final status = await platform.status();
      if (!mounted) return;
      if (!status.has(Need.location)) {
        await platform.openPermission(Need.location);
        if (mounted) context.showToast('Allow Location, then tap again.', status: UiStatus.info);
      } else if (!status.has(Need.locationServices)) {
        await platform.openPermission(Need.locationServices);
        if (mounted) context.showToast('Turn Location on, then tap again.', status: UiStatus.info);
      } else {
        final ssid = await platform.currentSsid();
        if (!mounted) return;
        if (ssid == null) {
          context.showToast('Not connected to Wi-Fi, or Android is hiding the name.', status: UiStatus.warning);
        } else {
          setState(() {
            _name.text = ssid;
            _error = null;
          });
        }
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _done() {
    final ssid = _name.text.trim();
    if (ssid.isEmpty) {
      setState(() => _error = 'Enter the network name.');
      return;
    }
    Navigator.of(context).pop(WifiCondition(ssid));
  }

  @override
  Widget build(BuildContext context) {
    return _Form(
      onDone: _done,
      children: [
        const UiAlert(
          'Android only shares the Wi-Fi network name with apps that have Location permission and Location '
          'turned on. Quietly reads only the network name, never where you are.',
          title: 'Why Location?',
        ),
        UiTextField(
          label: 'Network name (SSID)',
          hint: 'Exactly as it appears in Wi-Fi settings',
          controller: _name,
          error: _error,
          prefixIcon: Icons.wifi_rounded,
          onChanged: (_) => setState(() => _error = null),
        ),
        UiButton(
          'Use current network',
          icon: Icons.wifi_find_rounded,
          variant: UiButtonVariant.soft,
          loading: _busy,
          onPressed: _useCurrent,
        ),
        NeedNotice(widget.store, Need.location),
        NeedNotice(widget.store, Need.locationServices),
        NeedNotice(widget.store, Need.backgroundLocation),
      ],
    );
  }
}

class _TimeEditor extends StatefulWidget {
  const _TimeEditor({this.initial});

  final TimeCondition? initial;

  @override
  State<_TimeEditor> createState() => _TimeEditorState();
}

class _TimeEditorState extends State<_TimeEditor> {
  late int _start = widget.initial?.startMinute ?? 9 * 60;
  late int _end = widget.initial?.endMinute ?? 17 * 60;
  late Set<int> _days = {...(widget.initial?.days ?? TimeCondition.allDays)};

  TimeOfDay _tod(int minute) => TimeOfDay(hour: minute ~/ 60, minute: minute % 60);

  TimeCondition get _value => TimeCondition(startMinute: _start, endMinute: _end, days: _days);

  @override
  Widget build(BuildContext context) {
    return _Form(
      onDone: _days.isEmpty ? null : () => Navigator.of(context).pop(_value),
      children: [
        UiRow(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: UiTimeField(
                label: 'From',
                value: _tod(_start),
                clearable: false,
                onChanged: (t) => setState(() => _start = t == null ? _start : t.hour * 60 + t.minute),
              ),
            ),
            Expanded(
              child: UiTimeField(
                label: 'Until',
                value: _tod(_end),
                clearable: false,
                onChanged: (t) => setState(() => _end = t == null ? _end : t.hour * 60 + t.minute),
              ),
            ),
          ],
        ),
        UiSection(
          title: 'Days',
          subtitle: _value.overnight
              ? 'This window ends the next morning. It counts for the day it starts on.'
              : 'The window starts on these days.',
          child: UiFilterChips<int>(
            options: [for (var d = 1; d <= 7; d++) UiChoice(d, dayName(d))],
            values: _days,
            onChanged: (days) => setState(() => _days = days),
          ),
        ),
      ],
    );
  }
}

class _BluetoothEditor extends StatefulWidget {
  const _BluetoothEditor({required this.store, this.initial});

  final RulesStore store;
  final BluetoothCondition? initial;

  @override
  State<_BluetoothEditor> createState() => _BluetoothEditorState();
}

class _BluetoothEditorState extends State<_BluetoothEditor> {
  late final AppLifecycleListener _lifecycle;
  List<PairedDevice>? _devices;
  bool _allowed = true;

  @override
  void initState() {
    super.initState();
    _load();
    // Back from the permission dialog or settings: look again.
    _lifecycle = AppLifecycleListener(onResume: _load);
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final platform = widget.store.platform;
    final status = await platform.status();
    final devices = status.has(Need.bluetooth) ? await platform.pairedDevices() : null;
    if (!mounted) return;
    setState(() {
      _allowed = status.has(Need.bluetooth);
      _devices = devices;
    });
  }

  @override
  Widget build(BuildContext context) {
    final devices = _devices;
    if (!_allowed) {
      return UiColumn(
        gap: UiSpace.lg,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [NeedNotice(widget.store, Need.bluetooth)],
      );
    }
    if (devices == null) return const Padding(padding: EdgeInsets.all(UiSpace.xl), child: Center(child: UiSpinner()));
    if (devices.isEmpty) {
      return const UiEmptyState(
        compact: true,
        icon: Icons.bluetooth_disabled_rounded,
        title: 'No paired devices',
        message: 'Pair your car or headset in Android\'s Bluetooth settings first.',
      );
    }
    return UiListGroup(
      children: [
        for (final d in devices)
          UiListTile(
            d.name,
            subtitle: d.address,
            icon: Icons.bluetooth_rounded,
            selected: d.address == widget.initial?.address,
            onTap: () => Navigator.of(context).pop(BluetoothCondition(address: d.address, name: d.name)),
          ),
      ],
    );
  }
}

/// A percent slider. Pops the built value. With [need], shows its permission notice.
class _PercentEditor<T> extends StatefulWidget {
  const _PercentEditor({
    required this.label,
    required this.initial,
    required this.build,
    this.min = 0,
    this.max = 100,
    this.store,
    this.need,
  });

  final String label;
  final int initial;
  final int min;
  final int max;
  final T Function(int percent) build;
  final RulesStore? store;
  final Need? need;

  @override
  State<_PercentEditor<T>> createState() => _PercentEditorState<T>();
}

class _PercentEditorState<T> extends State<_PercentEditor<T>> {
  late int _value = widget.initial.clamp(widget.min, widget.max);

  @override
  Widget build(BuildContext context) {
    final store = widget.store, need = widget.need;
    return _Form(
      onDone: () => Navigator.of(context).pop(widget.build(_value)),
      children: [
        UiSlider(
          label: widget.label,
          value: _value.toDouble(),
          min: widget.min.toDouble(),
          max: widget.max.toDouble(),
          divisions: (widget.max - widget.min) ~/ 5,
          format: (v) => '${v.round()}%',
          onChanged: (v) => setState(() => _value = v.round()),
        ),
        if (store != null && need != null) NeedNotice(store, need),
      ],
    );
  }
}

/// Pick one of a few options (ringer mode, Do Not Disturb on/off).
class _ChoiceEditor<T> extends StatefulWidget {
  const _ChoiceEditor({
    required this.store,
    required this.options,
    required this.initial,
    required this.build,
    required this.need,
  });

  final RulesStore store;
  final List<UiChoice<T>> options;
  final T initial;
  final RuleAction Function(T value) build;

  /// The permission the chosen value needs, if any.
  final Need? Function(T value) need;

  @override
  State<_ChoiceEditor<T>> createState() => _ChoiceEditorState<T>();
}

class _ChoiceEditorState<T> extends State<_ChoiceEditor<T>> {
  late T _value = widget.initial;

  @override
  Widget build(BuildContext context) {
    final need = widget.need(_value);
    return _Form(
      onDone: () => Navigator.of(context).pop(widget.build(_value)),
      children: [
        UiChoiceChips<T>(
          options: widget.options,
          value: _value,
          onChanged: (v) => setState(() => _value = v),
        ),
        if (need != null) NeedNotice(widget.store, need),
      ],
    );
  }
}

class _AppEditor extends StatefulWidget {
  const _AppEditor({required this.store, this.initial});

  final RulesStore store;
  final OpenAppAction? initial;

  @override
  State<_AppEditor> createState() => _AppEditorState();
}

class _AppEditorState extends State<_AppEditor> {
  List<InstalledApp>? _apps;
  String? _package;

  @override
  void initState() {
    super.initState();
    final initial = widget.initial?.packageName;
    _package = (initial == null || initial.isEmpty) ? null : initial;
    widget.store.platform.apps().then((apps) {
      if (mounted) setState(() => _apps = apps);
    });
  }

  @override
  Widget build(BuildContext context) {
    final apps = _apps;
    if (apps == null) return const Padding(padding: EdgeInsets.all(UiSpace.xl), child: Center(child: UiSpinner()));
    final picked = apps.where((a) => a.packageName == _package).firstOrNull;
    return _Form(
      onDone: picked == null
          ? null
          : () => Navigator.of(context).pop(OpenAppAction(packageName: picked.packageName, label: picked.label)),
      children: [
        UiSelect<String>(
          label: 'App',
          hint: 'Choose an app',
          searchable: true,
          value: picked?.packageName,
          options: [for (final a in apps) UiOption(a.packageName, a.label)],
          onChanged: (v) => setState(() => _package = v),
        ),
        const UiAlert(
          'Android blocks apps from starting other apps in the background. With "Display over other apps" '
          'allowed, Quietly can open it anyway.',
        ),
        NeedNotice(widget.store, Need.overlay),
      ],
    );
  }
}

class _NotifyEditor extends StatefulWidget {
  const _NotifyEditor({required this.store, required this.initial});

  final RulesStore store;
  final String initial;

  @override
  State<_NotifyEditor> createState() => _NotifyEditorState();
}

class _NotifyEditorState extends State<_NotifyEditor> {
  late final _text = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _Form(
      onDone: () => Navigator.of(context).pop(NotifyAction(_text.text.trim())),
      children: [
        UiTextField(
          label: 'Message',
          hint: 'Shown with the rule name',
          controller: _text,
          maxLength: 80,
        ),
        NeedNotice(widget.store, Need.notifications),
      ],
    );
  }
}
