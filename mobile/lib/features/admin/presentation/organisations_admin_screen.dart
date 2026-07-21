import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../../core/design/tokens.dart';
import '../../../core/network/app_provider.dart';

class OrganisationsAdminScreen extends StatefulWidget {
  const OrganisationsAdminScreen({super.key});

  @override
  State<OrganisationsAdminScreen> createState() => _OrganisationsAdminScreenState();
}

class _OrganisationsAdminScreenState extends State<OrganisationsAdminScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final provider = Provider.of<AppProvider>(context, listen: false);
      provider.fetchPendingOrganisations();
      provider.fetchManagedOrganisations();
    });
  }

  Future<void> _refresh(AppProvider provider) async {
    await provider.fetchPendingOrganisations();
    await provider.fetchManagedOrganisations();
  }

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<AppProvider>(context);
    final pending = provider.pendingOrganisations;
    final orgs = provider.managedOrganisations;

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Organisations'),
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: () => _refresh(provider),
            ),
          ],
          bottom: TabBar(
            tabs: [
              Tab(text: 'Pending (${pending.length})'),
              Tab(text: 'All (${orgs.length})'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _PendingOrgsTab(pending: pending),
            _AllOrgsTab(orgs: orgs),
          ],
        ),
      ),
    );
  }
}

class _PendingOrgsTab extends StatelessWidget {
  const _PendingOrgsTab({required this.pending});

  final List<dynamic> pending;

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<AppProvider>(context, listen: false);

    if (pending.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'No organisation requests waiting for approval.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      itemCount: pending.length,
      separatorBuilder: (_, __) => const SizedBox(height: 14),
      itemBuilder: (context, index) {
        final org = pending[index];
        final orgName = org['name'] ?? org['org_name'] ?? 'Organisation';
        final orgSlug = org['slug'] ?? org['org_slug'] ?? '-';
        final orgEmail = org['email'] ?? org['org_email'];
        final orgPhone = org['phone'] ?? org['org_phone'];
        final orgAddress = org['address'] ?? org['org_address'];
        final ownerName = org['owner_name'] ?? org['ownerName'];
        final ownerEmail = org['owner_email'] ?? org['ownerEmail'];
        final ownerPhone = org['owner_phone'] ?? org['ownerPhone'];
        final createdAt = org['created_at'] ?? org['createdAt'];

        return Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(orgName.toString(), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                const SizedBox(height: 6),
                Text('Slug: $orgSlug', style: const TextStyle(fontWeight: FontWeight.w600)),
                Text('Status: ${org['status'] ?? 'pending'}'),
                if (orgEmail != null) Text('Org email: $orgEmail'),
                if (orgPhone != null) Text('Org phone: $orgPhone'),
                if (orgAddress != null) Text('Address: $orgAddress'),
                if (ownerName != null) Text('Owner: $ownerName'),
                if (ownerEmail != null) Text('Owner email: $ownerEmail'),
                if (org['owner_password'] != null) Text('Owner password: ${org['owner_password']}'),
                if (ownerPhone != null) Text('Owner phone: $ownerPhone'),
                if (createdAt != null)
                  Text('Submitted: $createdAt', style: const TextStyle(fontSize: 11, color: Colors.black54)),
                TextButton(
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => OrganisationDetailScreen(
                          orgIdOrSlug: org['id']?.toString() ?? orgSlug.toString(),
                        ),
                      ),
                    );
                  },
                  child: const Text('Open full details'),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () async {
                          final ok = await provider.approveOrganisation(org['id'].toString());
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  ok
                                      ? (provider.lastApproveSubscriptionSummary ??
                                          'Organisation approved — 7-day trial + 3-day grace started.')
                                      : (provider.lastActionError ?? 'Approve failed.'),
                                ),
                                backgroundColor: ok ? Colors.green : Colors.red,
                                duration: const Duration(seconds: 5),
                              ),
                            );
                          }
                        },
                        child: const Text('Approve'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () async {
                          final ok = await provider.rejectOrganisation(org['id'].toString());
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(ok ? 'Organisation rejected.' : (provider.lastActionError ?? 'Reject failed.')),
                                backgroundColor: ok ? Colors.orange : Colors.red,
                              ),
                            );
                          }
                        },
                        child: const Text('Reject'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _AllOrgsTab extends StatelessWidget {
  const _AllOrgsTab({required this.orgs});

  final List<dynamic> orgs;

  @override
  Widget build(BuildContext context) {
    if (orgs.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'No organisation records yet. Pending requests and approved orgs will appear here with their slug and registration details.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      itemCount: orgs.length,
      separatorBuilder: (_, __) => const SizedBox(height: 14),
      itemBuilder: (context, index) {
        final org = orgs[index];
        final status = (org['status'] ?? 'pending').toString();
        final slug = (org['slug'] ?? '').toString();
        final sub = (org['subscription_status'] ?? '').toString();
        String? trialLabel;
        String? graceLabel;
        final trialDt = DateTime.tryParse(org['trial_ends_at']?.toString() ?? '');
        final graceDt = DateTime.tryParse(org['grace_period_ends_at']?.toString() ?? '');
        if (trialDt != null) {
          final l = trialDt.toLocal();
          trialLabel =
              'Trial ends: ${l.day.toString().padLeft(2, '0')}/${l.month.toString().padLeft(2, '0')}/${l.year}';
        }
        if (graceDt != null) {
          final l = graceDt.toLocal();
          graceLabel =
              'Grace / lock: ${l.day.toString().padLeft(2, '0')}/${l.month.toString().padLeft(2, '0')}/${l.year}';
        }
        final subLine = [
          if (sub.isNotEmpty) 'Sub: $sub',
          if (trialLabel != null) trialLabel,
          if (graceLabel != null) graceLabel,
        ].join('\n');
        return Card(
          margin: EdgeInsets.zero,
          child: ListTile(
            title: Text(org['name']?.toString() ?? 'Organisation', style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text(
              'Slug: ${slug.isEmpty ? '-' : slug}\nStatus: $status'
              '${subLine.isEmpty ? '' : '\n$subLine'}',
              style: const TextStyle(height: 1.35, fontSize: 12),
            ),
            isThreeLine: true,
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => OrganisationDetailScreen(orgIdOrSlug: org['id']?.toString() ?? slug),
                ),
              );
            },
          ),
        );
      },
    );
  }
}

class OrganisationDetailScreen extends StatefulWidget {
  const OrganisationDetailScreen({super.key, required this.orgIdOrSlug});

  final String orgIdOrSlug;

  @override
  State<OrganisationDetailScreen> createState() => _OrganisationDetailScreenState();
}

class _OrganisationDetailScreenState extends State<OrganisationDetailScreen> {
  Map<String, dynamic>? _org;
  final _ownerEmail = TextEditingController();
  final _ownerPassword = TextEditingController();
  final _ownerPhone = TextEditingController();
  final _orgEmail = TextEditingController();
  final _orgPhone = TextEditingController();
  final _orgAddress = TextEditingController();
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final provider = Provider.of<AppProvider>(context, listen: false);
    await provider.fetchManagedOrganisations();
    final match = provider.managedOrganisations.cast<Map<String, dynamic>?>().firstWhere(
          (o) =>
              o?['id']?.toString() == widget.orgIdOrSlug ||
              (o?['slug']?.toString().toLowerCase() == widget.orgIdOrSlug.toLowerCase()),
          orElse: () => null,
        );
    if (!mounted) return;
    setState(() {
      _org = match;
      _ownerEmail.text = match?['owner_email']?.toString() ?? '';
      _ownerPassword.text = match?['owner_password']?.toString() ?? '';
      _ownerPhone.text = match?['owner_phone']?.toString() ?? '';
      _orgEmail.text = match?['email']?.toString() ?? '';
      _orgPhone.text = match?['phone']?.toString() ?? '';
      _orgAddress.text = match?['address']?.toString() ?? '';
      _loading = false;
    });
  }

  @override
  void dispose() {
    _ownerEmail.dispose();
    _ownerPassword.dispose();
    _ownerPhone.dispose();
    _orgEmail.dispose();
    _orgPhone.dispose();
    _orgAddress.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final org = _org;
    if (org == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Organisation')),
        body: const Center(child: Text('Organisation not found.')),
      );
    }

    final slug = (org['slug'] ?? '').toString();
    final status = (org['status'] ?? '').toString();
    final provider = Provider.of<AppProvider>(context, listen: false);
    final isPending = status.toLowerCase() == 'pending';

    return Scaffold(
      appBar: AppBar(title: Text(org['name']?.toString() ?? 'Organisation')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            color: BestieTokens.cBrandSoft,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Organisation slug (give this to the requester)', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: SelectableText(
                          slug.isEmpty ? '—' : slug,
                          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: 0.3),
                        ),
                      ),
                      if (slug.isNotEmpty)
                        IconButton(
                          tooltip: 'Copy slug',
                          onPressed: () async {
                            await Clipboard.setData(ClipboardData(text: slug));
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Slug copied')),
                              );
                            }
                          },
                          icon: const Icon(Icons.copy),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text('Status: $status'),
                  if (org['subscription_status'] != null)
                    Text('Subscription: ${org['subscription_status']}'),
                  if (DateTime.tryParse(org['trial_ends_at']?.toString() ?? '') != null)
                    Text(
                      'Trial ends: ${() {
                        final l = DateTime.parse(org['trial_ends_at'].toString()).toLocal();
                        return '${l.day.toString().padLeft(2, '0')}/${l.month.toString().padLeft(2, '0')}/${l.year}';
                      }()}',
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                  if (DateTime.tryParse(org['grace_period_ends_at']?.toString() ?? '') != null)
                    Text(
                      'Grace / access locks: ${() {
                        final l = DateTime.parse(org['grace_period_ends_at'].toString()).toLocal();
                        return '${l.day.toString().padLeft(2, '0')}/${l.month.toString().padLeft(2, '0')}/${l.year}';
                      }()}',
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                  if (org['id'] != null) Text('ID: ${org['id']}', style: const TextStyle(fontSize: 12, color: Colors.black54)),
                ],
              ),
            ),
          ),
          if (isPending) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: () async {
                      final ok = await provider.approveOrganisation(org['id'].toString());
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              ok
                                  ? (provider.lastApproveSubscriptionSummary ??
                                      'Organisation approved — 7-day trial + 3-day grace started.')
                                  : (provider.lastActionError ?? 'Approve failed.'),
                            ),
                            backgroundColor: ok ? Colors.green : Colors.red,
                            duration: const Duration(seconds: 5),
                          ),
                        );
                        if (ok) Navigator.of(context).pop();
                      }
                    },
                    child: const Text('Approve'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(
                    onPressed: () async {
                      final ok = await provider.rejectOrganisation(org['id'].toString());
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(ok ? 'Organisation rejected.' : (provider.lastActionError ?? 'Reject failed.')),
                            backgroundColor: ok ? Colors.orange : Colors.red,
                          ),
                        );
                        if (ok) Navigator.of(context).pop();
                      }
                    },
                    child: const Text('Reject'),
                  ),
                ),
              ],
            ),
          ],
          if (!isPending &&
              (provider.role ?? '').toLowerCase() == 'super_admin' &&
              org['id'] != null) ...[
            const SizedBox(height: 12),
            ElevatedButton.icon(
              icon: const Icon(Icons.restart_alt),
              label: const Text('Restart 7-day trial + 3-day grace'),
              onPressed: () async {
                final ok = await provider.updateOrganisationSubscription(
                  orgId: org['id'].toString(),
                );
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        ok
                            ? 'Subscription renewed: 7-day trial + 3-day grace.'
                            : (provider.lastActionError ?? 'Update failed.'),
                      ),
                      backgroundColor: ok ? Colors.green : Colors.red,
                    ),
                  );
                  if (ok) await _load();
                }
              },
            ),
          ],
          const SizedBox(height: 16),
          Card(
            color: Colors.orange.shade50,
            child: const Padding(
              padding: EdgeInsets.all(12),
              child: Text(
                'Production pending API often returns blank contact fields. '
                'If registration was done in this app, details appear automatically. '
                'Otherwise enter owner email/password here and tap Save — slug is always available to share.',
                style: TextStyle(fontSize: 12, height: 1.35),
              ),
            ),
          ),
          const SizedBox(height: 16),
          const Text('Organisation details', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 8),
          TextFormField(
            controller: _orgEmail,
            decoration: const InputDecoration(labelText: 'Org email'),
          ),
          TextFormField(
            controller: _orgPhone,
            decoration: const InputDecoration(labelText: 'Org phone'),
          ),
          TextFormField(
            controller: _orgAddress,
            decoration: const InputDecoration(labelText: 'Org address'),
          ),
          const SizedBox(height: 16),
          const Text('Owner credentials', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 8),
          TextFormField(
            controller: _ownerEmail,
            decoration: const InputDecoration(labelText: 'Owner email'),
          ),
          TextFormField(
            controller: _ownerPassword,
            decoration: const InputDecoration(labelText: 'Owner password'),
          ),
          TextFormField(
            controller: _ownerPhone,
            decoration: const InputDecoration(labelText: 'Owner phone'),
          ),
          const SizedBox(height: 20),
          ElevatedButton(
            onPressed: () async {
              await provider.updateManagedOrganisationDetails(widget.orgIdOrSlug, {
                'email': _orgEmail.text.trim(),
                'phone': _orgPhone.text.trim(),
                'address': _orgAddress.text.trim(),
                'owner_email': _ownerEmail.text.trim(),
                'owner_password': _ownerPassword.text.trim(),
                'owner_phone': _ownerPhone.text.trim(),
              });
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Details saved.'), backgroundColor: Colors.green),
                );
                await _load();
              }
            },
            child: const Text('Save details'),
          ),
        ],
      ),
    );
  }
}
