import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/network/app_provider.dart';
import '../data/telecaller_api.dart';

const _leadStatuses = ['NEW', 'CONTACTED', 'INTERESTED', 'FOLLOWUP', 'WON', 'LOST'];
const _statusFilters = ['ALL', ..._leadStatuses];
const _callOutcomes = [
  'REACHABLE',
  'NO_ANSWER',
  'NOT_RESPONDED',
  'BUSY',
  'SWITCHED_OFF',
  'FOLLOWUP_REQUIRED',
  'WRONG_NUMBER',
  'NOT_INTERESTED',
];

class TelecallerScreen extends StatefulWidget {
  const TelecallerScreen({super.key, this.useDesktopLayout = false});

  final bool useDesktopLayout;

  @override
  State<TelecallerScreen> createState() => _TelecallerScreenState();
}

class _TelecallerScreenState extends State<TelecallerScreen> with WidgetsBindingObserver {
  final _api = TelecallerApi();
  final _search = TextEditingController();
  Timer? _debounce;
  String? _statusFilter;
  List<Map<String, dynamic>> _leads = [];
  Map<String, dynamic>? _selectedLead;
  bool _loading = true;
  String? _error;
  String? _pendingCallId;
  Map<String, dynamic>? _pendingCallLead;

  bool get _canManageLeads {
    final role = Provider.of<AppProvider>(context, listen: false).role ?? '';
    return role == 'SUPER_ADMIN' ||
        role == 'REGIONAL_MANAGER' ||
        role == 'SALES_MANAGER';
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _fetch();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _search.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _pendingCallId != null) {
      _showCallOutcomeSheet();
    }
  }

  Future<void> _fetch() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final items = await _api.listLeads(
        q: _search.text.trim().isEmpty ? null : _search.text.trim(),
        status: _statusFilter,
      );
      if (!mounted) return;
      setState(() {
        _leads = items;
        _loading = false;
        if (_selectedLead != null) {
          _selectedLead = items.cast<Map<String, dynamic>?>().firstWhere(
                (l) => l?['id'] == _selectedLead!['id'],
                orElse: () => null,
              );
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = formatTelecallerError(e);
        _loading = false;
      });
    }
  }

  void _onSearchChanged(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 220), _fetch);
  }

  Future<void> _callLead(Map<String, dynamic> lead) async {
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Use mobile app'),
          content: const Text('Please use your mobile app to complete call.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK')),
          ],
        ),
      );
      return;
    }

    final phone = (lead['phone'] ?? '').toString().trim().replaceAll(RegExp(r'[^\d+]'), '');
    if (phone.isEmpty) {
      _toast('Lead has no phone number', isError: true);
      return;
    }

    try {
      final response = await _api.callLead(lead['id'].toString(), mode: 'PHONE');
      final call = response['call'] as Map?;
      final callId = call?['id']?.toString();
      if (callId == null) throw Exception('Could not start call log');

      _pendingCallId = callId;
      _pendingCallLead = lead;

      final launched = await launchUrl(Uri(scheme: 'tel', path: phone), mode: LaunchMode.externalApplication);
      if (!launched) {
        _pendingCallId = null;
        _pendingCallLead = null;
        throw Exception('Could not open phone app');
      }
      _toast('Phone call opened');
    } catch (e) {
      if (mounted) _toast(formatTelecallerError(e), isError: true);
    }
  }

  Future<void> _showCallOutcomeSheet() async {
    final callId = _pendingCallId;
    final lead = _pendingCallLead;
    if (callId == null || lead == null) return;

    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => _CallOutcomeSheet(
        leadName: lead['name']?.toString() ?? 'Lead',
        onSave: (outcome, notes) async {
          await _api.updateCallOutcome(callId, outcome: outcome, notes: notes);
        },
      ),
    );

    if (saved == true) {
      _pendingCallId = null;
      _pendingCallLead = null;
      await _fetch();
    }
  }

  void _toast(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red.shade700 : const Color(0xFF1E3A8A),
      ),
    );
  }

  Future<void> _showCreateLeadSheet() async {
    final created = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => _CreateLeadSheet(api: _api),
    );
    if (created == true) await _fetch();
  }

  Future<void> _showBulkAssignSheet() async {
    final assigned = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => _BulkAssignSheet(api: _api),
    );
    if (assigned == true) await _fetch();
  }

  Future<void> _updateLeadStatus(String leadId, String status) async {
    try {
      await _api.updateLead(leadId, {'status': status});
      await _fetch();
      _toast('Lead status updated');
    } catch (e) {
      _toast(formatTelecallerError(e), isError: true);
    }
  }

  Color _statusColor(String status, BuildContext context) {
    return switch (status) {
      'WON' => Colors.green.shade100,
      'CONTACTED' => Colors.blue.shade100,
      'INTERESTED' || 'FOLLOWUP' => Colors.amber.shade100,
      'LOST' => Colors.grey.shade300,
      _ => const Color(0xFFDBEAFE),
    };
  }

  Color _statusTextColor(String status) {
    return switch (status) {
      'WON' => Colors.green.shade800,
      'CONTACTED' => Colors.blue.shade800,
      'INTERESTED' || 'FOLLOWUP' => Colors.amber.shade900,
      'LOST' => Colors.grey.shade700,
      _ => const Color(0xFF1E3A8A),
    };
  }

  Widget _statusBadge(String status) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: _statusColor(status, context),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        status,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: _statusTextColor(status),
          letterSpacing: 0.4,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.useDesktopLayout || Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      return _buildDesktopLayout(context);
    }
    return _buildMobileLayout(context);
  }

  Widget _buildMobileLayout(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: TextField(
            controller: _search,
            onChanged: _onSearchChanged,
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search_rounded, size: 18),
              hintText: 'Find a lead',
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(999),
                borderSide: BorderSide.none,
              ),
              isDense: true,
            ),
          ),
        ),
        SizedBox(
          height: 40,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            itemCount: _statusFilters.length,
            separatorBuilder: (_, __) => const SizedBox(width: 6),
            itemBuilder: (ctx, i) {
              final s = _statusFilters[i];
              final active = (s == 'ALL' && _statusFilter == null) || s == _statusFilter;
              return ChoiceChip(
                label: Text(s),
                selected: active,
                onSelected: (_) {
                  setState(() => _statusFilter = s == 'ALL' ? null : s);
                  _fetch();
                },
                selectedColor: const Color(0xFFDBEAFE),
                labelStyle: TextStyle(
                  color: active ? const Color(0xFF1E3A8A) : Colors.grey.shade700,
                  fontWeight: FontWeight.w600,
                  fontSize: 11,
                ),
              );
            },
          ),
        ),
        Expanded(child: _buildLeadList(onTap: _callLead, onLongPress: _showStatusSheet)),
      ],
    );
  }

  Widget _buildDesktopLayout(BuildContext context) {
    final selected = _selectedLead;
    return Row(
      children: [
        SizedBox(
          width: 360,
          child: ColoredBox(
            color: const Color(0xFFF9FAFB),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
                  child: Row(
                    children: [
                      const Expanded(
                        child: Text('Leads', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                      ),
                      if (_canManageLeads)
                        TextButton.icon(
                          onPressed: _showBulkAssignSheet,
                          icon: const Icon(Icons.upload_file_rounded, size: 16),
                          label: const Text('Bulk assign'),
                        ),
                      FilledButton.icon(
                        onPressed: _showCreateLeadSheet,
                        icon: const Icon(Icons.add_rounded, size: 16),
                        label: const Text('Add lead'),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: TextField(
                    controller: _search,
                    onChanged: _onSearchChanged,
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search_rounded, size: 18),
                      hintText: 'Search by name, phone, company',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: _buildLeadList(
                    onTap: (lead) => setState(() => _selectedLead = lead),
                    selectedId: selected?['id']?.toString(),
                  ),
                ),
              ],
            ),
          ),
        ),
        const VerticalDivider(width: 1),
        Expanded(
          child: selected == null
              ? const Center(child: Text('Select a lead to see details.', style: TextStyle(color: Colors.grey)))
              : Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  selected['name']?.toString() ?? '',
                                  style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '${selected['company'] ?? ''} · ${selected['phone'] ?? ''}',
                                  style: TextStyle(color: Colors.grey.shade600),
                                ),
                              ],
                            ),
                          ),
                          FilledButton.icon(
                            onPressed: () => _callLead(selected),
                            icon: const Icon(Icons.phone),
                            label: const Text('Click to call'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: [
                          _detailCard(
                            'Status',
                            DropdownButton<String>(
                              value: selected['status']?.toString() ?? 'NEW',
                              items: _leadStatuses
                                  .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                                  .toList(),
                              onChanged: (value) {
                                if (value != null) {
                                  _updateLeadStatus(selected['id'].toString(), value);
                                }
                              },
                            ),
                          ),
                          _detailCard(
                            'Next follow up',
                            Text(
                              selected['nextFollowAt'] != null
                                  ? DateTime.tryParse(selected['nextFollowAt'].toString())
                                          ?.toLocal()
                                          .toString()
                                          .split('.')
                                          .first ??
                                      '—'
                                  : '—',
                            ),
                          ),
                          SizedBox(
                            width: double.infinity,
                            child: _detailCard(
                              'Notes',
                              Text(selected['notes']?.toString() ?? 'No notes yet.'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
        ),
      ],
    );
  }

  Widget _detailCard(String label, Widget child) {
    return Container(
      width: 280,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF9FAFB),
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
          const SizedBox(height: 6),
          child,
        ],
      ),
    );
  }

  Widget _buildLeadList({
    required void Function(Map<String, dynamic> lead) onTap,
    void Function(Map<String, dynamic> lead)? onLongPress,
    String? selectedId,
  }) {
    if (_loading && _leads.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(child: Text(_error!, style: const TextStyle(color: Colors.red)));
    }
    if (_leads.isEmpty) {
      return const Center(child: Text('No leads. Add one to get started.'));
    }

    return RefreshIndicator(
      onRefresh: _fetch,
      child: ListView.separated(
        itemCount: _leads.length,
        separatorBuilder: (_, __) => const Divider(height: 1, indent: 72),
        itemBuilder: (ctx, i) {
          final lead = _leads[i];
          final name = lead['name']?.toString() ?? '—';
          final company = lead['company']?.toString() ?? '';
          final phone = lead['phone']?.toString() ?? '';
          final status = lead['status']?.toString() ?? 'NEW';
          final isSelected = selectedId == lead['id']?.toString();

          return Material(
            color: isSelected ? const Color(0xFFDBEAFE) : Colors.transparent,
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor: const Color(0xFFDBEAFE),
                child: Text(
                  name.isNotEmpty ? name[0].toUpperCase() : '?',
                  style: const TextStyle(color: Color(0xFF1E3A8A), fontWeight: FontWeight.bold),
                ),
              ),
              title: Text(name, style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text([company, phone].where((s) => s.isNotEmpty).join(' · ')),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  GestureDetector(
                    onTap: onLongPress != null ? () => onLongPress(lead) : null,
                    child: _statusBadge(status),
                  ),
                  IconButton(
                    icon: Icon(Icons.call_rounded, color: Colors.green.shade600),
                    onPressed: () => _callLead(lead),
                  ),
                ],
              ),
              onTap: () => onTap(lead),
              onLongPress: onLongPress != null ? () => onLongPress(lead) : null,
            ),
          );
        },
      ),
    );
  }

  Future<void> _showStatusSheet(Map<String, dynamic> lead) async {
    final updated = await showModalBottomSheet<bool>(
      context: context,
      builder: (ctx) => _LeadStatusSheet(
        current: lead['status']?.toString() ?? 'NEW',
        onSelect: (status) => _api.updateLead(lead['id'].toString(), {'status': status}),
      ),
    );
    if (updated == true) await _fetch();
  }
}

class TelecallerDashboardScreen extends StatelessWidget {
  const TelecallerDashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<AppProvider>(context);
    final isWide = MediaQuery.sizeOf(context).width >= 900;

    return Scaffold(
      backgroundColor: const Color(0xFFF3F4F6),
      appBar: AppBar(
        title: const Text('Telecaller'),
        actions: [
          if (provider.role == 'SUPER_ADMIN' ||
              provider.role == 'REGIONAL_MANAGER' ||
              provider.role == 'SALES_MANAGER')
            IconButton(
              tooltip: 'Bulk assign leads',
              icon: const Icon(Icons.upload_file_rounded),
              onPressed: () {
                final state = context.findAncestorStateOfType<_TelecallerScreenState>();
                state?._showBulkAssignSheet();
              },
            ),
          IconButton(
            tooltip: 'Add lead',
            icon: const Icon(Icons.add_rounded),
            onPressed: () {
              final state = context.findAncestorStateOfType<_TelecallerScreenState>();
              state?._showCreateLeadSheet();
            },
          ),
          IconButton(
            tooltip: 'Logout',
            icon: const Icon(Icons.logout),
            onPressed: () async {
              await provider.logout('telecaller-mobile-device');
            },
          ),
        ],
      ),
      body: TelecallerScreen(useDesktopLayout: isWide),
    );
  }
}

class _CreateLeadSheet extends StatefulWidget {
  const _CreateLeadSheet({required this.api});
  final TelecallerApi api;

  @override
  State<_CreateLeadSheet> createState() => _CreateLeadSheetState();
}

class _CreateLeadSheetState extends State<_CreateLeadSheet> {
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _company = TextEditingController();
  final _email = TextEditingController();
  final _source = TextEditingController();
  final _notes = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _company.dispose();
    _email.dispose();
    _source.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_name.text.trim().isEmpty || _phone.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Name and phone are required')),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      await widget.api.createLead({
        'name': _name.text.trim(),
        'phone': _phone.text.trim(),
        'company': _company.text.trim().isEmpty ? null : _company.text.trim(),
        'email': _email.text.trim().isEmpty ? null : _email.text.trim(),
        'source': _source.text.trim().isEmpty ? null : _source.text.trim(),
        'notes': _notes.text.trim().isEmpty ? null : _notes.text.trim(),
        'status': 'NEW',
      });
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(formatTelecallerError(e)), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Add lead', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          TextField(controller: _name, decoration: const InputDecoration(labelText: 'Lead name *')),
          TextField(controller: _phone, decoration: const InputDecoration(labelText: 'Phone *')),
          TextField(controller: _company, decoration: const InputDecoration(labelText: 'Company')),
          TextField(controller: _email, decoration: const InputDecoration(labelText: 'Email')),
          TextField(controller: _source, decoration: const InputDecoration(labelText: 'Source')),
          TextField(
            controller: _notes,
            decoration: const InputDecoration(labelText: 'Notes'),
            maxLines: 3,
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: _saving ? null : _submit,
            child: _saving
                ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Create lead'),
          ),
        ],
      ),
    );
  }
}

class _BulkAssignSheet extends StatefulWidget {
  const _BulkAssignSheet({required this.api});
  final TelecallerApi api;

  @override
  State<_BulkAssignSheet> createState() => _BulkAssignSheetState();
}

class _BulkAssignSheetState extends State<_BulkAssignSheet> {
  final _rows = TextEditingController();
  final _source = TextEditingController(text: 'admin-upload');
  final _recordsPerDay = TextEditingController(text: '100');
  String _startDate = DateTime.now().toIso8601String().split('T').first;
  String _endDate = DateTime.now().toIso8601String().split('T').first;
  List<Map<String, dynamic>> _telecallers = [];
  final Set<String> _selectedIds = {};
  String? _filePath;
  String? _fileName;
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _loadTelecallers();
  }

  @override
  void dispose() {
    _rows.dispose();
    _source.dispose();
    _recordsPerDay.dispose();
    super.dispose();
  }

  Future<void> _loadTelecallers() async {
    try {
      final items = await widget.api.listTelecallers();
      if (mounted) setState(() {
        _telecallers = items;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<Map<String, dynamic>> _parseRows() {
    final lines = _rows.text.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).toList();
    final dataLines = lines.isNotEmpty && lines.first.toLowerCase().contains('phone')
        ? lines.sublist(1)
        : lines;
    return dataLines.map((line) {
      final parts = line.split(',').map((p) => p.trim()).toList();
      return {
        'name': parts.isNotEmpty ? parts[0] : '',
        'phone': parts.length > 1 ? parts[1] : '',
        'company': parts.length > 2 ? parts[2] : null,
        'email': parts.length > 3 ? parts[3] : null,
        'notes': parts.length > 4 ? parts.sublist(4).join(', ') : null,
      };
    }).where((r) => r['name'].toString().isNotEmpty && r['phone'].toString().isNotEmpty).toList();
  }

  Future<void> _submit() async {
    if (_selectedIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select at least one telecaller')),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      if (_filePath != null) {
        await widget.api.bulkDistributeFile(
          filePath: _filePath!,
          fileName: _fileName ?? 'leads.csv',
          telecallerIds: _selectedIds.toList(),
          startDate: _startDate,
          endDate: _endDate,
          recordsPerTelecallerPerDay: int.tryParse(_recordsPerDay.text) ?? 100,
          source: _source.text.trim().isEmpty ? null : _source.text.trim(),
        );
      } else {
        await widget.api.bulkDistribute(
          telecallerIds: _selectedIds.toList(),
          startDate: _startDate,
          endDate: _endDate,
          recordsPerTelecallerPerDay: int.tryParse(_recordsPerDay.text) ?? 100,
          source: _source.text.trim().isEmpty ? null : _source.text.trim(),
          records: _parseRows(),
        );
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(formatTelecallerError(e)), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Bulk assign leads', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    initialValue: _startDate,
                    decoration: const InputDecoration(labelText: 'Start date (YYYY-MM-DD)'),
                    onChanged: (v) => _startDate = v,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextFormField(
                    initialValue: _endDate,
                    decoration: const InputDecoration(labelText: 'End date (YYYY-MM-DD)'),
                    onChanged: (v) => _endDate = v,
                  ),
                ),
              ],
            ),
            TextField(
              controller: _recordsPerDay,
              decoration: const InputDecoration(labelText: 'Records per telecaller per day'),
              keyboardType: TextInputType.number,
            ),
            TextField(controller: _source, decoration: const InputDecoration(labelText: 'Source')),
            const SizedBox(height: 8),
            const Text('Telecallers', style: TextStyle(fontWeight: FontWeight.w600)),
            if (_loading) const LinearProgressIndicator(),
            ..._telecallers.map(
              (t) => CheckboxListTile(
                value: _selectedIds.contains(t['id']),
                onChanged: (checked) {
                  setState(() {
                    if (checked == true) {
                      _selectedIds.add(t['id'].toString());
                    } else {
                      _selectedIds.remove(t['id'].toString());
                    }
                  });
                },
                title: Text(t['name']?.toString() ?? t['email']?.toString() ?? ''),
              ),
            ),
            OutlinedButton.icon(
              onPressed: () async {
                final result = await FilePicker.platform.pickFiles(
                  type: FileType.custom,
                  allowedExtensions: ['csv', 'xlsx', 'xlsm'],
                );
                if (result != null && result.files.single.path != null) {
                  setState(() {
                    _filePath = result.files.single.path;
                    _fileName = result.files.single.name;
                  });
                }
              },
              icon: const Icon(Icons.upload_file),
              label: Text(_fileName ?? 'Upload Excel / CSV file'),
            ),
            TextField(
              controller: _rows,
              enabled: _filePath == null,
              maxLines: 8,
              decoration: const InputDecoration(
                labelText: 'Customer data',
                hintText: 'name, phone, company, email, notes',
              ),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: _saving ? null : _submit,
              child: _saving
                  ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Assign leads'),
            ),
          ],
        ),
      ),
    );
  }
}

class _LeadStatusSheet extends StatefulWidget {
  const _LeadStatusSheet({required this.current, required this.onSelect});
  final String current;
  final Future<void> Function(String status) onSelect;

  @override
  State<_LeadStatusSheet> createState() => _LeadStatusSheetState();
}

class _LeadStatusSheetState extends State<_LeadStatusSheet> {
  late String _selected;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _selected = widget.current;
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Change status', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          ..._leadStatuses.map(
            (s) => RadioListTile<String>(
              value: s,
              groupValue: _selected,
              onChanged: (v) => setState(() => _selected = v!),
              title: Text(s),
            ),
          ),
          FilledButton(
            onPressed: _saving
                ? null
                : () async {
                    setState(() => _saving = true);
                    try {
                      await widget.onSelect(_selected);
                      if (mounted) Navigator.pop(context, true);
                    } catch (e) {
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(formatTelecallerError(e)), backgroundColor: Colors.red),
                        );
                      }
                    } finally {
                      if (mounted) setState(() => _saving = false);
                    }
                  },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }
}

class _CallOutcomeSheet extends StatefulWidget {
  const _CallOutcomeSheet({required this.leadName, required this.onSave});
  final String leadName;
  final Future<void> Function(String outcome, String? notes) onSave;

  @override
  State<_CallOutcomeSheet> createState() => _CallOutcomeSheetState();
}

class _CallOutcomeSheetState extends State<_CallOutcomeSheet> {
  String? _outcome;
  final _notes = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Call outcome — ${widget.leadName}',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          ..._callOutcomes.map(
            (o) => RadioListTile<String>(
              value: o,
              groupValue: _outcome,
              onChanged: (v) => setState(() => _outcome = v),
              title: Text(o.replaceAll('_', ' ')),
              dense: true,
            ),
          ),
          TextField(
            controller: _notes,
            decoration: const InputDecoration(labelText: 'Notes (optional)'),
            maxLines: 2,
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: _saving || _outcome == null
                ? null
                : () async {
                    setState(() => _saving = true);
                    try {
                      await widget.onSave(_outcome!, _notes.text.trim().isEmpty ? null : _notes.text.trim());
                      if (mounted) Navigator.pop(context, true);
                    } catch (e) {
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(formatTelecallerError(e)), backgroundColor: Colors.red),
                        );
                      }
                    } finally {
                      if (mounted) setState(() => _saving = false);
                    }
                  },
            child: const Text('Save outcome'),
          ),
        ],
      ),
    );
  }
}
