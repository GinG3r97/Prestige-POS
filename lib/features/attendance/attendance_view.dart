import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../app/app_state.dart';
import '../../data/supabase_client.dart';
import 'requests_view.dart';
import '../../design_system/colors.dart';
import '../../design_system/spacing.dart';
import '../../design_system/typography.dart';
import '../widgets/push_toast.dart';

/// Owner-facing attendance review: per-day punches with selfies, geofence
/// flags, and computed hours. Reads attendance_punches (owner RLS).
class AttendanceView extends StatefulWidget {
  const AttendanceView({super.key, this.embedded = false});

  /// When embedded in the Attendance hub, render just the body (the hub owns
  /// the app bar + the OT/UT/Leave rail).
  final bool embedded;

  @override
  State<AttendanceView> createState() => _AttendanceViewState();
}

class _Punch {
  final String kind; // 'in' | 'out'
  final DateTime at;
  final String? selfie; // data URL
  final bool flagged;
  final String? flagReason;
  final int? distanceM;
  _Punch(this.kind, this.at, this.selfie, this.flagged, this.flagReason, this.distanceM);
}

class _AttendanceViewState extends State<AttendanceView> {
  DateTime _day = DateTime.now();
  bool _loading = true;
  String? _error;
  final Map<String, List<_Punch>> _byEmployee = {};

  bool _geoSet = false;
  int _radius = 200;
  bool _settingLoc = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final tid = context.read<AppState>().currentTenantDbId;
    if (tid == null) {
      setState(() {
        _loading = false;
        _error = 'No store selected.';
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
      _byEmployee.clear();
    });
    // Day bounds in Manila (UTC+8) expressed as UTC instants.
    final start = DateTime.utc(_day.year, _day.month, _day.day)
        .subtract(const Duration(hours: 8));
    final end = start.add(const Duration(days: 1));
    try {
      final rows = await supabase
          .from('attendance_punches')
          .select(
              'employee_name, kind, punched_at, selfie, distance_m, within_geofence, flagged, flag_reason')
          .eq('tenant_id', tid)
          .gte('punched_at', start.toIso8601String())
          .lt('punched_at', end.toIso8601String())
          .order('punched_at');
      for (final r in rows as List) {
        final m = r as Map<String, dynamic>;
        final name = (m['employee_name'] as String?) ?? 'Unknown';
        (_byEmployee[name] ??= []).add(_Punch(
          m['kind'] as String,
          DateTime.parse(m['punched_at'] as String).toLocal(),
          m['selfie'] as String?,
          (m['flagged'] as bool?) ?? false,
          m['flag_reason'] as String?,
          (m['distance_m'] as num?)?.toInt(),
        ));
      }
      final t = await supabase
          .from('tenants')
          .select('geo_lat, geo_radius_m')
          .eq('id', tid)
          .maybeSingle();
      _geoSet = t != null && t['geo_lat'] != null;
      _radius = (t?['geo_radius_m'] as num?)?.toInt() ?? 200;
      setState(() => _loading = false);
    } catch (e) {
      setState(() {
        _loading = false;
        _error = 'Could not load attendance.';
      });
    }
  }

  bool get _isToday =>
      DateUtils.isSameDay(_day, DateTime.now());

  String _hoursFor(List<_Punch> punches) {
    Duration total = Duration.zero;
    DateTime? openIn;
    for (final p in punches) {
      if (p.kind == 'in') {
        openIn = p.at;
      } else if (p.kind == 'out' && openIn != null) {
        total += p.at.difference(openIn);
        openIn = null;
      }
    }
    final stillIn = openIn != null;
    final h = total.inMinutes / 60.0;
    return stillIn
        ? '${h.toStringAsFixed(1)}h · still in'
        : '${h.toStringAsFixed(1)}h';
  }

  @override
  Widget build(BuildContext context) {
    final names = _byEmployee.keys.toList()..sort();
    final body = Column(
      children: [
        _setupBar(),
        _dateBar(),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
                  ? Center(
                      child: Text(_error!,
                          style: YFont.body().copyWith(color: YColor.inkMuted)))
                  : names.isEmpty
                      ? Center(
                          child: Text('No punches on this day.',
                              style: YFont.body()
                                  .copyWith(color: YColor.inkSubtle)))
                      : ListView(
                          padding: const EdgeInsets.all(16),
                          children: [
                            for (final name in names)
                              _employeeCard(name, _byEmployee[name]!),
                          ],
                        ),
        ),
      ],
    );
    if (widget.embedded) {
      return Container(color: YColor.surface2, child: body);
    }
    return Scaffold(
      backgroundColor: YColor.surface2,
      appBar: AppBar(
        title: const Text('Attendance'),
        backgroundColor: YColor.surface1,
        foregroundColor: YColor.ink,
        elevation: 0,
        actions: [
          IconButton(
            tooltip: 'Requests',
            icon: const Icon(Icons.assignment_outlined),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const RequestsView()),
            ),
          ),
        ],
      ),
      body: body,
    );
  }

  Widget _setupBar() {
    return Container(
      color: YColor.surface1,
      padding: const EdgeInsets.fromLTRB(16, 10, 12, 10),
      child: Row(
        children: [
          Icon(Icons.location_on,
              size: 18, color: _geoSet ? YColor.success : YColor.inkMuted),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _geoSet
                  ? 'Store location set · within ${_radius}m'
                  : 'Store location not set',
              style: YFont.caption().copyWith(
                  color: _geoSet ? YColor.ink : YColor.inkMuted,
                  fontWeight: FontWeight.w600),
            ),
          ),
          TextButton.icon(
            onPressed: _settingLoc ? null : _setLocation,
            icon: _settingLoc
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.my_location, size: 16),
            label: Text(_geoSet ? 'Update' : 'Set location'),
            style: TextButton.styleFrom(foregroundColor: YColor.brandDeep),
          ),
          IconButton(
            tooltip: 'Show QR',
            onPressed: _showQr,
            icon: const Icon(Icons.qr_code_2, color: YColor.brandDeep),
          ),
        ],
      ),
    );
  }

  Future<void> _setLocation() async {
    // Let the owner pick the allowed radius, then capture the device GPS.
    final radius = await showModalBottomSheet<int>(
      context: context,
      backgroundColor: YColor.surface1,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Allowed distance from store',
                style: YFont.titleMD().copyWith(fontSize: 16)),
            const SizedBox(height: 4),
            Text('Stand inside your store, then pick how far staff may clock in.',
                style: YFont.caption().copyWith(color: YColor.inkMuted)),
            const SizedBox(height: 16),
            Wrap(
              spacing: 10,
              children: [100, 200, 300, 500]
                  .map((r) => ElevatedButton(
                        onPressed: () => Navigator.pop(context, r),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: YColor.surface2,
                          foregroundColor: YColor.ink,
                          elevation: 0,
                        ),
                        child: Text('${r}m'),
                      ))
                  .toList(),
            ),
          ],
        ),
      ),
    );
    if (radius == null || !mounted) return;

    setState(() => _settingLoc = true);
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        _toast('Location is off',
            subtitle: 'Turn on location services, then try again.',
            icon: Icons.location_disabled);
        return;
      }
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        _toast('Permission needed',
            subtitle: 'Allow location access to set the store.',
            icon: Icons.location_disabled);
        return;
      }
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
      );
      await supabase.rpc('set_store_geofence', params: {
        'p_lat': pos.latitude,
        'p_lng': pos.longitude,
        'p_radius': radius,
      });
      if (!mounted) return;
      _toast('Geofence is on',
          subtitle: 'Store location saved. Staff can only clock in here.',
          icon: Icons.check_circle);
      await _load();
    } catch (_) {
      _toast('Couldn’t save location',
          subtitle: 'Something went wrong. Please try again.',
          icon: Icons.error_outline);
    } finally {
      if (mounted) setState(() => _settingLoc = false);
    }
  }

  void _showQr() {
    final code = context.read<AppState>().storeCode;
    final url = code != null
        ? 'https://pos.prestigeitsolutions.tech/portal?store=$code'
        : 'https://pos.prestigeitsolutions.tech/portal';
    showDialog(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: YColor.surface1,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Scan to open the portal',
                  style: YFont.titleMD().copyWith(fontSize: 16)),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: YColor.hairline),
                ),
                child: QrImageView(data: url, size: 220),
              ),
              const SizedBox(height: 12),
              if (code != null) ...[
                Text('Store ID $code',
                    style: YFont.caption()
                        .copyWith(color: YColor.inkSubtle, fontFamily: 'Menlo')),
                const SizedBox(height: 4),
              ],
              Text('Staff scan this, then sign in with their email (one-time code).',
                  textAlign: TextAlign.center,
                  style: YFont.caption().copyWith(color: YColor.inkMuted)),
            ],
          ),
        ),
      ),
    );
  }

  void _toast(String title, {String? subtitle, IconData icon = Icons.place_outlined}) {
    if (!mounted) return;
    PushToast.show(context, title: title, subtitle: subtitle, leadingIcon: icon);
  }

  Widget _dateBar() {
    return Container(
      color: YColor.surface1,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      child: Row(
        children: [
          IconButton(
            onPressed: () {
              setState(() => _day = _day.subtract(const Duration(days: 1)));
              _load();
            },
            icon: const Icon(Icons.chevron_left),
          ),
          Expanded(
            child: Center(
              child: Text(
                _isToday ? 'Today' : DateFormat('EEE, MMM d').format(_day),
                style: YFont.titleMD().copyWith(fontSize: 15),
              ),
            ),
          ),
          IconButton(
            onPressed: _isToday
                ? null
                : () {
                    setState(() => _day = _day.add(const Duration(days: 1)));
                    _load();
                  },
            icon: const Icon(Icons.chevron_right),
          ),
        ],
      ),
    );
  }

  Widget _employeeCard(String name, List<_Punch> punches) {
    final anyFlag = punches.any((p) => p.flagged);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: YColor.surface1,
        borderRadius: BorderRadius.circular(YRadius.lg),
        border: Border.all(
            color: anyFlag ? YColor.danger.withValues(alpha: 0.4) : YColor.hairline),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
            child: Row(
              children: [
                Expanded(
                  child: Text(name,
                      style: YFont.titleMD().copyWith(fontSize: 16)),
                ),
                Text(_hoursFor(punches),
                    style: YFont.bodyStrong().copyWith(color: YColor.brandDeep)),
              ],
            ),
          ),
          const Divider(height: 1, color: YColor.hairline),
          for (final p in punches) _punchRow(p),
        ],
      ),
    );
  }

  Widget _punchRow(_Punch p) {
    final isIn = p.kind == 'in';
    return InkWell(
      onTap: p.selfie == null ? null : () => _viewSelfie(p),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            _selfieThumb(_decode(p.selfie)),
            const SizedBox(width: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: isIn
                    ? YColor.success.withValues(alpha: 0.15)
                    : YColor.surface3,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(isIn ? 'IN' : 'OUT',
                  style: YFont.caption().copyWith(
                      fontWeight: FontWeight.w800,
                      color: isIn ? YColor.success : YColor.inkMuted)),
            ),
            const SizedBox(width: 10),
            Text(DateFormat('h:mm a').format(p.at),
                style: YFont.bodyStrong()),
            const Spacer(),
            if (p.flagged)
              Tooltip(
                message: p.flagReason ?? 'flagged',
                child: const Icon(Icons.flag, size: 16, color: YColor.danger),
              )
            else if (p.distanceM != null)
              Text('${p.distanceM}m',
                  style: YFont.caption().copyWith(color: YColor.inkSubtle)),
          ],
        ),
      ),
    );
  }

  Widget _selfieThumb(Uint8List? bytes) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: bytes == null
          ? Container(
              width: 38,
              height: 38,
              color: YColor.surface3,
              child: const Icon(Icons.person, size: 18, color: YColor.inkSubtle),
            )
          : Image.memory(bytes, width: 38, height: 38, fit: BoxFit.cover),
    );
  }

  void _viewSelfie(_Punch p) {
    final bytes = _decode(p.selfie);
    if (bytes == null) return;
    showDialog(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: Colors.transparent,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Image.memory(bytes, fit: BoxFit.contain),
            ),
            const SizedBox(height: 10),
            Text(
              '${p.kind == 'in' ? 'Clock in' : 'Clock out'} · ${DateFormat('h:mm a').format(p.at)}',
              style: YFont.bodyStrong().copyWith(color: Colors.white),
            ),
          ],
        ),
      ),
    );
  }

  static Uint8List? _decode(String? dataUrl) {
    if (dataUrl == null || dataUrl.isEmpty) return null;
    final comma = dataUrl.indexOf(',');
    final raw = comma >= 0 ? dataUrl.substring(comma + 1) : dataUrl;
    try {
      return base64Decode(raw);
    } catch (_) {
      return null;
    }
  }
}
