import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/design/tokens.dart';
import '../../../core/network/app_provider.dart';
import '../../../core/utils/device_location.dart';

/// Common shop types for Google-style category suggestions while typing.
const _shopCategorySuggestions = <String>[
  'Plywood',
  'Hardware',
  'Sanitary',
  'Electrical',
  'Electronics',
  'Diagnostics',
  'Diagnostic Centre',
  'Pathology',
  'Pharmacy',
  'Medical Store',
  'Clinic',
  'Hospital',
  'Grocery',
  'Kirana',
  'Supermarket',
  'Furniture',
  'Interior',
  'Paint',
  'Cement',
  'Tiles',
  'Glass',
  'Aluminium',
  'Steel',
  'Automobile',
  'Bike Showroom',
  'Car Accessories',
  'Mobile Shop',
  'Computer',
  'Stationery',
  'Book Store',
  'Bakery',
  'Restaurant',
  'Hotel',
  'Salon',
  'Beauty Parlour',
  'Tailor',
  'Garments',
  'Footwear',
  'Jewellery',
  'Optical',
  'Dental',
  'Lab',
  'Xerox',
  'Print Shop',
  'Courier',
  'Travel Agency',
  'Real Estate',
  'Construction',
  'Plumbing',
  'AC Repair',
  'Welding',
  'Fabrication',
];

/// Prospects tab — search shops + saved prospects with convert.
class LeadsTab extends StatefulWidget {
  const LeadsTab({super.key});

  @override
  State<LeadsTab> createState() => _LeadsTabState();
}

class _LeadsTabState extends State<LeadsTab> {
  final _queryController = TextEditingController();
  final _queryFocus = FocusNode();
  final _areaController = TextEditingController();
  final _areaFocus = FocusNode();
  final List<String> _selectedAreas = [];
  bool _isSearching = false;
  String? _searchError;
  int _section = 0; // 0 find shops, 1 saved

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<AppProvider>(context, listen: false).fetchSavedLeads();
    });
  }

  @override
  void dispose() {
    _queryController.dispose();
    _queryFocus.dispose();
    _areaController.dispose();
    _areaFocus.dispose();
    super.dispose();
  }

  List<String> _categoryMatches(String raw) {
    final q = raw.trim().toLowerCase();
    if (q.isEmpty) return const [];
    final starts = <String>[];
    final contains = <String>[];
    for (final name in _shopCategorySuggestions) {
      final lower = name.toLowerCase();
      if (lower == q) continue;
      if (lower.startsWith(q)) {
        starts.add(name);
      } else if (lower.contains(q)) {
        contains.add(name);
      }
    }
    return [...starts, ...contains].take(8).toList();
  }

  void _addAreaChip(String raw) {
    final area = raw.trim();
    if (area.isEmpty) return;
    final exists = _selectedAreas.any((a) => a.toLowerCase() == area.toLowerCase());
    if (exists) {
      _areaController.clear();
      return;
    }
    setState(() {
      _selectedAreas.add(area);
      _areaController.clear();
      _searchError = null;
    });
  }

  void _removeAreaChip(String area) {
    setState(() => _selectedAreas.remove(area));
  }

  void _commitAreaFromField() {
    final text = _areaController.text.trim();
    if (text.isEmpty) return;
    // Support comma / slash separated paste: "kukatpally, moosapet"
    final parts = text
        .split(RegExp(r'[,;/|]+'))
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty);
    for (final part in parts) {
      _addAreaChip(part);
    }
  }

  Future<(double?, double?)> _resolveSearchOrigin({required bool needGps}) async {
    if (!needGps) return (null, null);
    final pos = await DeviceLocation.resolvePosition(timeLimit: const Duration(seconds: 4));
    if (pos == null) return (null, null);
    return (pos.latitude, pos.longitude);
  }

  Future<void> _searchShops(AppProvider provider) async {
    final query = _queryController.text.trim();
    _commitAreaFromField();
    final areas = List<String>.from(_selectedAreas);

    if (query.isEmpty && areas.isEmpty) {
      setState(() => _searchError = 'Enter a shop type (e.g. Plywood) and/or add areas (e.g. Kukatpally).');
      return;
    }

    setState(() {
      _isSearching = true;
      _searchError = null;
    });

    try {
      if (areas.isEmpty) {
        final origin = await _resolveSearchOrigin(needGps: true);
        await provider.searchBusinessDirectory(
          query: query,
          latitude: origin.$1,
          longitude: origin.$2,
          radiusKm: 10,
        );
      } else {
        // Search each area and merge — same category across all selected localities.
        final merged = <Map<String, dynamic>>[];
        final seen = <String>{};
        for (final area in areas) {
          await provider.searchBusinessDirectory(
            query: query,
            area: area,
            radiusKm: 8,
          );
          for (final lead in provider.nearbyLeads) {
            final key = [
              lead['businessName'],
              lead['address'],
              lead['gpsLat'],
              lead['gpsLng'],
            ].join('|').toLowerCase();
            if (seen.add(key)) {
              merged.add({
                ...lead,
                'searchArea': area,
              });
            }
          }
        }
        provider.setNearbyLeads(merged);
      }

      if (provider.nearbyLeads.isEmpty && mounted) {
        final areaLabel = areas.isEmpty ? '' : ' in ${areas.join(', ')}';
        setState(() {
          _searchError = query.isEmpty
              ? 'No shops found$areaLabel.'
              : 'No matching shops for "$query"$areaLabel. '
                  'Try another keyword (e.g. Plywood, Hardware, Diagnostics).';
        });
      }
    } catch (_) {
      setState(() => _searchError = 'Shop directory unreachable. Check internet and try again.');
    } finally {
      if (mounted) setState(() => _isSearching = false);
    }
  }

  Future<void> _convertLead(AppProvider provider, Map lead) async {
    if (provider.isConvertingLead) return;
    final id = lead['id']?.toString();
    if (id == null || id.isEmpty) return;

    final ok = await provider.convertLeadToOutlet(id);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          ok
              ? 'Converted to outlet. Open Home → Planned to visit it.'
              : (provider.lastActionError ?? 'Convert failed.'),
        ),
        backgroundColor: ok ? Colors.green : Colors.red,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final appProvider = Provider.of<AppProvider>(context);
    final bottomPad = MediaQuery.of(context).padding.bottom + 88;
    final converting = appProvider.isConvertingLead;

    return Stack(
      children: [
        ListView(
          padding: EdgeInsets.fromLTRB(16, 16, 16, bottomPad),
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'PROSPECTS',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.grey),
                  ),
                ),
                TextButton.icon(
                  onPressed: () {
                    setState(() => _section = 1);
                    appProvider.fetchSavedLeads();
                  },
                  icon: const Icon(Icons.bookmark_outline, size: 18),
                  label: Text('SAVED (${appProvider.savedLeads.length})'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SegmentedButton<int>(
              showSelectedIcon: false,
              segments: [
                const ButtonSegment(
                  value: 0,
                  label: Text('Find shops'),
                  icon: Icon(Icons.search, size: 16),
                ),
                ButtonSegment(
                  value: 1,
                  label: Text('Saved (${appProvider.savedLeads.length})'),
                  icon: const Icon(Icons.bookmark, size: 16),
                ),
              ],
              selected: {_section},
              onSelectionChanged: (s) {
                setState(() => _section = s.first);
                if (s.first == 1) appProvider.fetchSavedLeads();
              },
            ),
            const SizedBox(height: 16),
            if (_section == 0) ...[
              Card(
                color: Colors.blue.shade50,
                child: const Padding(
                  padding: EdgeInsets.all(12.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Find shops in an area', style: TextStyle(fontWeight: FontWeight.bold, color: BestieTokens.cBrand)),
                      SizedBox(height: 6),
                      Text(
                        'Type a shop type for suggestions (e.g. ply → Plywood). '
                        'Add multiple areas as chips, then search across all of them.',
                        style: TextStyle(fontSize: 13, color: Colors.black87),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              RawAutocomplete<String>(
                textEditingController: _queryController,
                focusNode: _queryFocus,
                optionsBuilder: (textEditingValue) {
                  return _categoryMatches(textEditingValue.text);
                },
                displayStringForOption: (o) => o,
                onSelected: (value) {
                  _queryController.text = value;
                  _queryController.selection = TextSelection.collapsed(offset: value.length);
                },
                fieldViewBuilder: (context, textController, focusNode, onFieldSubmitted) {
                  return TextField(
                    controller: textController,
                    focusNode: focusNode,
                    decoration: const InputDecoration(
                      labelText: 'Shop name / type',
                      hintText: 'e.g. Plywood, Diagnostics, Hardware',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.storefront),
                      helperText: 'Suggestions appear as you type',
                    ),
                    textInputAction: TextInputAction.next,
                    onSubmitted: (_) => onFieldSubmitted(),
                  );
                },
                optionsViewBuilder: (context, onSelected, options) {
                  final opts = options.toList();
                  if (opts.isEmpty) return const SizedBox.shrink();
                  return Align(
                    alignment: Alignment.topLeft,
                    child: Material(
                      elevation: 4,
                      borderRadius: BorderRadius.circular(10),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 220, maxWidth: 420),
                        child: ListView.builder(
                          padding: EdgeInsets.zero,
                          shrinkWrap: true,
                          itemCount: opts.length,
                          itemBuilder: (context, index) {
                            final option = opts[index];
                            return ListTile(
                              dense: true,
                              leading: const Icon(Icons.search, size: 18, color: BestieTokens.cBrand),
                              title: Text(option),
                              onTap: () => onSelected(option),
                            );
                          },
                        ),
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _areaController,
                focusNode: _areaFocus,
                decoration: InputDecoration(
                  labelText: 'Area / locality',
                  hintText: 'e.g. Kukatpally — tap + or press Enter',
                  border: const OutlineInputBorder(),
                  prefixIcon: const Icon(Icons.location_city),
                  suffixIcon: IconButton(
                    tooltip: 'Add area',
                    icon: const Icon(Icons.add_circle, color: BestieTokens.cBrand),
                    onPressed: _commitAreaFromField,
                  ),
                  helperText: _selectedAreas.isEmpty
                      ? 'Add one or more areas, then SEARCH'
                      : '${_selectedAreas.length} area(s) selected',
                ),
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _commitAreaFromField(),
              ),
              if (_selectedAreas.isNotEmpty) ...[
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _selectedAreas.map((area) {
                    return Container(
                      padding: const EdgeInsets.fromLTRB(12, 6, 6, 6),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF3F4F6),
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: const Color(0xFFD1D5DB)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 180),
                            child: Text(
                              area,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                                color: Colors.black87,
                              ),
                            ),
                          ),
                          const SizedBox(width: 4),
                          InkWell(
                            borderRadius: BorderRadius.circular(12),
                            onTap: () => _removeAreaChip(area),
                            child: const Padding(
                              padding: EdgeInsets.all(4),
                              child: Icon(Icons.close, size: 16, color: Colors.black54),
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ],
              const SizedBox(height: 10),
              ElevatedButton.icon(
                onPressed: _isSearching ? null : () => _searchShops(appProvider),
                icon: _isSearching
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.search),
                label: Text(_isSearching ? 'Searching…' : 'SEARCH SHOPS'),
              ),
              if (_searchError != null) ...[
                const SizedBox(height: 12),
                Text(_searchError!, style: const TextStyle(color: Colors.orange, fontSize: 12)),
              ],
              const SizedBox(height: 16),
              Text(
                'RESULTS (${appProvider.nearbyLeads.length})',
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey),
              ),
              const SizedBox(height: 8),
              if (appProvider.nearbyLeads.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Text(
                    'No results yet. Enter shop type, add areas, then tap SEARCH SHOPS.',
                    style: TextStyle(color: Colors.grey),
                    textAlign: TextAlign.center,
                  ),
                )
              else
                ...appProvider.nearbyLeads.map((lead) => _ResultCard(lead: lead)),
            ] else ...[
              const Text(
                'Bookmark shops from Find shops, then convert them into outlets for today’s plan.',
                style: TextStyle(fontSize: 13, color: Colors.black54),
              ),
              const SizedBox(height: 12),
              if (appProvider.savedLeads.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 32),
                  child: Text(
                    'No saved prospects yet. Search shops and tap the bookmark icon.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey),
                  ),
                )
              else
                ...appProvider.savedLeads.map((lead) {
                  final map = Map<String, dynamic>.from(lead as Map);
                  final status = (map['leadStatus'] ?? 'NEW').toString().toUpperCase();
                  final converted = status == 'CONVERTED';
                  final isThisConverting = appProvider.convertingLeadId == map['id']?.toString();
                  return Card(
                    margin: const EdgeInsets.only(bottom: 10),
                    color: converted ? Colors.green.shade50 : Colors.white,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              CircleAvatar(
                                backgroundColor: converted ? Colors.green : Colors.orange,
                                foregroundColor: Colors.white,
                                child: Icon(converted ? Icons.check : Icons.bookmark),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      map['businessName']?.toString() ?? 'Saved outlet',
                                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                                    ),
                                    if ((map['address'] ?? '').toString().isNotEmpty)
                                      Text(map['address'].toString(), style: const TextStyle(fontSize: 12, color: Colors.black87)),
                                    if ((map['businessCategory'] ?? '').toString().isNotEmpty)
                                      Text(map['businessCategory'].toString(), style: const TextStyle(fontSize: 12, color: Colors.blueGrey)),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          if (converted)
                            const Text(
                              'Already converted — find it under Home → Planned.',
                              style: TextStyle(color: Colors.green, fontWeight: FontWeight.w600),
                            )
                          else
                            ElevatedButton.icon(
                              onPressed: converting ? null : () => _convertLead(appProvider, map),
                              icon: isThisConverting
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                    )
                                  : const Icon(Icons.transform),
                              label: Text(isThisConverting ? 'Converting…' : 'CONVERT TO OUTLET'),
                            ),
                        ],
                      ),
                    ),
                  );
                }),
            ],
          ],
        ),
        if (converting)
          Positioned.fill(
            child: AbsorbPointer(
              child: ColoredBox(
                color: Colors.black.withValues(alpha: 0.35),
                child: const Center(
                  child: Card(
                    child: Padding(
                      padding: EdgeInsets.symmetric(horizontal: 28, vertical: 22),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CircularProgressIndicator(),
                          SizedBox(height: 14),
                          Text('Converting to outlet…', style: TextStyle(fontWeight: FontWeight.w600)),
                          SizedBox(height: 4),
                          Text('Please wait — do not tap again.', style: TextStyle(fontSize: 12, color: Colors.black54)),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _ResultCard extends StatelessWidget {
  const _ResultCard({required this.lead});

  final Map<String, dynamic> lead;

  String _distanceLabel(dynamic distance) {
    if (distance is! num) return '';
    final meters = distance.round();
    if (meters < 0) return '';
    if (meters < 1000) return '${meters}m away';
    return '${(meters / 1000).toStringAsFixed(1)} km away';
  }

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<AppProvider>(context, listen: false);
    final distanceLabel = _distanceLabel(lead['distanceMeters']);
    final phone = lead['contactPhone']?.toString() ?? '';
    final category = lead['businessCategory']?.toString() ?? '';
    final address = lead['address']?.toString() ?? '';
    final imageUrl = lead['featuredImage']?.toString() ?? '';
    final searchArea = lead['searchArea']?.toString() ?? '';

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 10, 6, 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                width: 72,
                height: 72,
                child: imageUrl.isNotEmpty
                    ? Image.network(
                        imageUrl,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Container(
                          color: Colors.grey.shade200,
                          child: const Icon(Icons.storefront, color: Colors.grey),
                        ),
                      )
                    : Container(
                        color: Colors.grey.shade200,
                        child: const Icon(Icons.storefront, color: Colors.grey),
                      ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    lead['businessName']?.toString() ?? 'Shop',
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                  ),
                  if (address.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(address, style: const TextStyle(fontSize: 13, color: Colors.black87, height: 1.35)),
                  ],
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      if (searchArea.isNotEmpty)
                        Text(searchArea, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: BestieTokens.cBrand)),
                      if (distanceLabel.isNotEmpty)
                        Text(distanceLabel, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: BestieTokens.cBrand)),
                      if (category.isNotEmpty)
                        Text(category, style: const TextStyle(fontSize: 12, color: Colors.blueGrey)),
                      if (phone.isNotEmpty)
                        Text(phone, style: const TextStyle(fontSize: 12, color: Colors.grey)),
                    ],
                  ),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.bookmark_add_outlined, color: BestieTokens.cBrand),
              tooltip: 'Save as Lead',
              onPressed: () async {
                final success = await provider.saveLeadRecord(
                  lead['businessName']?.toString() ?? 'Shop',
                  lead['businessCategory']?.toString() ?? 'Business',
                  lead['contactPhone']?.toString() ?? '',
                  lead['contactEmail']?.toString() ?? '',
                  double.tryParse(lead['gpsLat']?.toString() ?? '') ?? 0,
                  double.tryParse(lead['gpsLng']?.toString() ?? '') ?? 0,
                  address: lead['address']?.toString() ?? '',
                );
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        success
                            ? 'Saved. Open Prospects → Saved to convert to an outlet.'
                            : 'Could not save lead.',
                      ),
                      backgroundColor: success ? Colors.green : Colors.red,
                    ),
                  );
                }
              },
            ),
          ],
        ),
      ),
    );
  }
}
