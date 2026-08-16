import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/repository.dart';

/// Daily reminder switch plus its time, shown on the deck list.
///
/// Deliberately not buried in a settings page: it is the single highest-value
/// setting in the app, and one nobody goes looking for.
class ReminderTile extends ConsumerStatefulWidget {
  const ReminderTile({super.key});

  @override
  ConsumerState<ReminderTile> createState() => _ReminderTileState();
}

class _ReminderTileState extends ConsumerState<ReminderTile> {
  bool? _enabled;
  ({int hour, int minute})? _time;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final reminders = await ref.read(remindersProvider.future);
    final enabled = await reminders.isEnabled();
    final time = await reminders.time();
    if (!mounted) return;
    setState(() {
      _enabled = enabled;
      _time = time;
    });
  }

  Future<void> _toggle(bool on) async {
    setState(() => _busy = true);
    final reminders = await ref.read(remindersProvider.future);
    if (on) {
      // Android 13+ won't show anything without this, and the schedule call
      // succeeds regardless — so a refused permission has to be surfaced here
      // or the switch would sit on while nothing ever arrives.
      final granted = await reminders.requestPermission();
      if (!granted) {
        if (mounted) {
          setState(() => _busy = false);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Мэдэгдлийн зөвшөөрөл өгөгдсөнгүй')),
          );
        }
        return;
      }
      await reminders.enable();
    } else {
      await reminders.disable();
    }
    if (!mounted) return;
    setState(() => _busy = false);
    await _refresh();
  }

  Future<void> _pickTime() async {
    final current = _time;
    if (current == null) return;
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: current.hour, minute: current.minute),
    );
    if (picked == null) return;
    final reminders = await ref.read(remindersProvider.future);
    await reminders.enable(hour: picked.hour, minute: picked.minute);
    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final enabled = _enabled;
    final time = _time;
    if (enabled == null || time == null) return const SizedBox.shrink();

    final label =
        '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SwitchListTile(
          secondary: const Icon(Icons.notifications_outlined),
          title: const Text('Өдөр тутмын сануулга'),
          subtitle: Text(enabled ? 'Идэвхтэй' : 'Унтраалттай'),
          value: enabled,
          onChanged: _busy ? null : _toggle,
          dense: true,
        ),
        // Only offered once the reminder is on — an editable time for a
        // disabled reminder is a control that does nothing.
        if (enabled)
          ListTile(
            dense: true,
            leading: const SizedBox(width: 24),
            title: const Text('Сануулах цаг'),
            trailing: Text(label,
                style: const TextStyle(fontWeight: FontWeight.w600)),
            onTap: _busy ? null : _pickTime,
          ),
      ],
    );
  }
}
