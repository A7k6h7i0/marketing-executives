import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../../core/constants/api_endpoints.dart';
import '../../../core/design/shell.dart';
import '../../../core/design/tokens.dart';
import '../../../core/design/widgets.dart';
import '../../../core/network/app_provider.dart';
import '../../../core/utils/device_id.dart';
import '../../../core/utils/device_location.dart';
import 'package:intl/intl.dart';
import 'package:image_picker/image_picker.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' as latlong;
import 'package:url_launcher/url_launcher.dart';

import '../../admin/presentation/organisations_admin_screen.dart';
import '../../admin/presentation/products_admin_screen.dart';
import '../../auth/presentation/blink_selfie_capture_screen.dart';
import 'leads_tab.dart';
import 'outlet_location_pin_picker.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  int _currentIndex = 0;
  AppProvider? _appProvider;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _appProvider = context.read<AppProvider>();
      _appProvider!.addListener(_handleProviderUpdates);
      if (_appProvider!.todayPlan != null) {
        _appProvider!.startAutoVisitMonitoring();
      }
    });
  }

  @override
  void dispose() {
    _appProvider?.removeListener(_handleProviderUpdates);
    _appProvider?.stopAutoVisitMonitoring();
    super.dispose();
  }

  void _handleProviderUpdates() {
    if (!mounted || _appProvider == null) return;
    final autoOutlet = _appProvider!.lastAutoRegisteredOutlet;
    if (autoOutlet == null) return;

    _appProvider!.clearLastAutoRegisteredOutlet();
    final outletName = autoOutlet['name']?.toString() ?? 'Outlet';
    final completed = autoOutlet['completed'] == true;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          completed
              ? 'Visit auto-completed at $outletName after minimum stay.'
              : 'Visit auto-registered at $outletName after minimum stay time.',
        ),
        backgroundColor: Colors.green,
      ),
    );

    if (completed) return;

    final matchedOutlet = _appProvider!.plannedOutlets.cast<dynamic>().firstWhere(
      (o) => o is Map && o['id']?.toString() == autoOutlet['id']?.toString(),
      orElse: () => null,
    );
    if (matchedOutlet is Map<String, dynamic>) {
      showActiveVisitActionsDialog(context, _appProvider!, matchedOutlet);
    }
  }

  @override
  Widget build(BuildContext context) {
    final appProvider = Provider.of<AppProvider>(context);

    final tabs = [
      const HomeTab(),
      const MapTrackingTab(),
      const LeadsTab(),
      const IncidentsTab(),
    ];

    final onDuty = appProvider.attendanceStatus == 'LOGGED_IN' ||
        appProvider.attendanceStatus == 'PRESENT';

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        // Close dialogs / bottom sheets first.
        final nav = Navigator.of(context);
        if (nav.canPop()) {
          nav.pop();
          return;
        }
        // Switch to Home tab instead of exiting.
        if (_currentIndex != 0) {
          setState(() => _currentIndex = 0);
          return;
        }
        final leave = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Exit app?'),
            content: const Text('Do you want to close Marketing Executives?'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Stay')),
              ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Exit')),
            ],
          ),
        );
        if (leave == true && context.mounted) {
          SystemNavigator.pop();
        }
      },
      child: Scaffold(
      backgroundColor: BestieTokens.cBg,
      extendBody: false,
      appBar: _currentIndex == 0
          ? BestieShellAppBar(
              actions: [
                IconButton(
                  icon: const Icon(Icons.sync),
                  tooltip: 'Sync Offline Data',
                  onPressed: () async {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Synchronizing offline logs...')),
                    );
                    await appProvider.syncOfflineData();
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.logout),
                  tooltip: 'Logout',
                  onPressed: () async {
                    final deviceId = await DeviceId.get();
                    await appProvider.logout(deviceId);
                  },
                ),
              ],
            )
          : AppBar(
              title: Text(_currentIndex == 1
                  ? 'Route & Tracking'
                  : _currentIndex == 2
                      ? 'Prospects'
                      : 'Field Reports'),
              actions: [
                IconButton(
                  icon: const Icon(Icons.sync),
                  tooltip: 'Sync Offline Data',
                  onPressed: () async {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Synchronizing offline logs...')),
                    );
                    await appProvider.syncOfflineData();
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.logout),
                  tooltip: 'Logout',
                  onPressed: () async {
                    final deviceId = await DeviceId.get();
                    await appProvider.logout(deviceId);
                  },
                ),
              ],
            ),
      body: IndexedStack(
        index: _currentIndex,
        children: tabs,
      ),
      floatingActionButton: onDuty
          ? FloatingActionButton.extended(
              heroTag: 'break_fab',
              backgroundColor: appProvider.activeBreak != null ? BestieTokens.cText : BestieTokens.cBrand,
              foregroundColor: Colors.white,
              icon: Icon(
                appProvider.activeBreak != null ? Icons.pause_circle_filled : Icons.free_breakfast,
              ),
              label: Text(appProvider.activeBreak != null ? 'End Break' : 'Take Break'),
              onPressed: () {
                if (appProvider.activeBreak != null) {
                  _showEndBreakDialog(context, appProvider);
                } else {
                  _showStartBreakDialog(context, appProvider);
                }
              },
            )
          : null,
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      bottomNavigationBar: BestieBottomNav(
        currentIndex: _currentIndex,
        onTap: (index) {
          setState(() {
            _currentIndex = index;
          });
        },
        items: const [
          BestieNavItem(Icons.dashboard_outlined, Icons.dashboard, 'Home'),
          BestieNavItem(Icons.map_outlined, Icons.map, 'Route'),
          BestieNavItem(Icons.explore_outlined, Icons.explore, 'Prospects'),
          BestieNavItem(Icons.report_problem_outlined, Icons.report_problem, 'Reports'),
        ],
      ),
    ),
    );
  }

  void _showStartBreakDialog(BuildContext context, AppProvider provider) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        final bottomPad = MediaQuery.of(context).padding.bottom;
        return Padding(
          padding: EdgeInsets.fromLTRB(24, 24, 24, bottomPad + 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Select Break Category',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: BestieTokens.cBrand),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              ListTile(
                leading: const Icon(Icons.coffee, color: BestieTokens.cBrand),
                title: const Text('Coffee Break'),
                onTap: () {
                  provider.startBreakSession('COFFEE');
                  Navigator.pop(context);
                },
              ),
              ListTile(
                leading: const Icon(Icons.restaurant, color: BestieTokens.cBrandStrong),
                title: const Text('Lunch Break'),
                onTap: () {
                  provider.startBreakSession('LUNCH');
                  Navigator.pop(context);
                },
              ),
              ListTile(
                leading: const Icon(Icons.person_pin, color: BestieTokens.cText),
                title: const Text('Personal Break'),
                onTap: () {
                  provider.startBreakSession('PERSONAL');
                  Navigator.pop(context);
                },
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
            ],
          ),
        );
      },
    );
  }

  void _showEndBreakDialog(BuildContext context, AppProvider provider) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('End Break?'),
          content: const Text('Are you sure you want to end your active break session and resume working hours tracking?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('CANCEL'),
            ),
            ElevatedButton(
              onPressed: () async {
                final duration = await provider.endBreakSession();
                if (context.mounted) {
                  Navigator.pop(context);
                  if (duration) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Break ended. Total break time today: ${provider.totalBreakFormatted}'),
                        backgroundColor: Colors.green,
                      ),
                    );
                  }
                }
              },
              child: const Text('CONFIRM'),
            ),
          ],
        );
      },
    );
  }
}

// ---------------- HOME TAB ----------------
void showActiveVisitActionsDialog(BuildContext context, AppProvider provider, Map<String, dynamic> outlet) {
  if (!context.mounted) return;

  Future.microtask(() {
    if (!context.mounted) return;
    showDialog(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text('Visit Started: ${outlet['name']}'),
          content: const Text('Selfie and location are verified. You can now add sales/order details or check out when the visit is finished.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('LATER'),
            ),
            ElevatedButton.icon(
              icon: const Icon(Icons.add_shopping_cart),
              label: const Text('ORDER / SALES'),
              onPressed: () {
                Navigator.pop(dialogContext);
                showOrderCatalogScreen(context, provider);
              },
            ),
            ElevatedButton.icon(
              icon: const Icon(Icons.directions_walk),
              label: const Text('CHECK-OUT'),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
              onPressed: () async {
                await provider.checkoutOutlet();
                if (dialogContext.mounted) Navigator.pop(dialogContext);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Visit checked out successfully.'), backgroundColor: Colors.green),
                  );
                }
              },
            ),
          ],
        );
      },
    );
  });
}

void showOrderCatalogScreen(BuildContext context, AppProvider provider) {
  String initialRemarks = '';
  if (provider.activeVisit != null && provider.activeVisit!['remarks'] != null) {
    initialRemarks = provider.activeVisit!['remarks'];
  }
  final remarksController = TextEditingController(text: initialRemarks);

  Future<void> openSheet() async {
    await provider.fetchProductCatalog();
    if (!context.mounted) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetContext) {
        return Consumer<AppProvider>(
          builder: (context, app, _) {
            return StatefulBuilder(
              builder: (context, setModalState) {
                final media = MediaQuery.of(context);
                final bottomInset = media.viewInsets.bottom;
                final safeBottom = media.padding.bottom;
                final sheetHeight = ((media.size.height - bottomInset) * 0.92).clamp(280.0, media.size.height);
                final catalog = app.productCatalog;

                Future<void> openProductEditor({Map? existing}) async {
                  final nameCtrl = TextEditingController(text: existing?['name']?.toString() ?? '');
                  final sizeCtrl = TextEditingController(text: existing?['size']?.toString() ?? '');
                  final priceCtrl = TextEditingController(
                    text: existing == null
                        ? ''
                        : (double.tryParse(existing['unitPrice']?.toString() ?? '') ?? 0).toStringAsFixed(2),
                  );
                  final saved = await showDialog<bool>(
                    context: context,
                    builder: (ctx) {
                      final width = MediaQuery.of(ctx).size.width * 0.88;
                      InputDecoration fieldDecoration(String hint) => InputDecoration(
                            hintText: hint,
                            isDense: true,
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: const BorderSide(color: BestieTokens.cBorder),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: const BorderSide(color: BestieTokens.cBrand, width: 1.6),
                            ),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                          );

                      Widget labeledField({
                        required String label,
                        required TextEditingController controller,
                        required String hint,
                        TextInputType? keyboardType,
                      }) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              label,
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: BestieTokens.cTextSoft,
                              ),
                            ),
                            const SizedBox(height: 6),
                            TextField(
                              controller: controller,
                              keyboardType: keyboardType,
                              decoration: fieldDecoration(hint),
                            ),
                          ],
                        );
                      }

                      return AlertDialog(
                        title: Text(existing == null ? 'Add product' : 'Edit product'),
                        content: SizedBox(
                          width: width,
                          child: SingleChildScrollView(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                labeledField(
                                  label: 'Product name',
                                  controller: nameCtrl,
                                  hint: 'e.g. Premium Plywood',
                                ),
                                const SizedBox(height: 14),
                                labeledField(
                                  label: 'Size',
                                  controller: sizeCtrl,
                                  hint: 'e.g. 18mm, 1 box',
                                ),
                                const SizedBox(height: 14),
                                labeledField(
                                  label: 'Unit price',
                                  controller: priceCtrl,
                                  hint: '0.00',
                                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                ),
                              ],
                            ),
                          ),
                        ),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save')),
                        ],
                      );
                    },
                  );
                  if (saved != true) return;
                  final price = double.tryParse(priceCtrl.text.trim()) ?? -1;
                  final ok = await app.upsertExecutiveProduct(
                    id: existing?['id']?.toString(),
                    existingSku: existing?['sku']?.toString(),
                    name: nameCtrl.text,
                    size: sizeCtrl.text,
                    unitPrice: price,
                  );
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(ok ? 'Product saved.' : (app.lastActionError ?? 'Save failed.')),
                      backgroundColor: ok ? Colors.green : Colors.red,
                    ),
                  );
                  setModalState(() {});
                }

                return Padding(
                  padding: EdgeInsets.only(bottom: bottomInset),
                  child: SizedBox(
                    height: sheetHeight,
                    child: Column(
                      children: [
                        Expanded(
                          child: SingleChildScrollView(
                            padding: const EdgeInsets.fromLTRB(16, 24, 16, 12),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                const Text(
                                  'Products Used / Order & Remarks',
                                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: BestieTokens.cBrand),
                                  textAlign: TextAlign.center,
                                ),
                                const SizedBox(height: 12),
                                Row(
                                  children: [
                                    const Expanded(
                                      child: Text(
                                        'SELECT PRODUCTS THIS CUSTOMER USES OR ORDERS',
                                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey),
                                      ),
                                    ),
                                    TextButton.icon(
                                      onPressed: () => openProductEditor(),
                                      icon: const Icon(Icons.add, size: 18),
                                      label: const Text('ADD'),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Container(
                                  height: 200,
                                  decoration: BoxDecoration(
                                    border: Border.all(color: Colors.grey[300]!),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: catalog.isEmpty
                                      ? const Center(
                                          child: Padding(
                                            padding: EdgeInsets.all(16),
                                            child: Text(
                                              'No products yet. Tap ADD to create one.',
                                              textAlign: TextAlign.center,
                                              style: TextStyle(color: Colors.grey),
                                            ),
                                          ),
                                        )
                                      : ListView.builder(
                                          itemCount: catalog.length,
                                          itemBuilder: (context, idx) {
                                            final prod = catalog[idx];
                                            final displayPrice =
                                                double.tryParse(prod['unitPrice']?.toString() ?? '') ?? 0.0;
                                            final size = prod['size']?.toString() ?? '';
                                            final isCustom = prod['isCustom'] == true;
                                            final isFallback = prod['isFallback'] == true;
                                            return ListTile(
                                              dense: true,
                                              title: Text(
                                                prod['name']?.toString() ?? 'Product',
                                                style: const TextStyle(fontWeight: FontWeight.bold),
                                              ),
                                              subtitle: Text(
                                                [
                                                  if (size.isNotEmpty) 'Size: $size',
                                                  'SKU: ${prod['sku']} · ₹${displayPrice.toStringAsFixed(2)}',
                                                  if (isCustom) 'Your product',
                                                  if (isFallback) 'Default product',
                                                ].join('\n'),
                                              ),
                                              isThreeLine: true,
                                              trailing: Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  IconButton(
                                                    icon: const Icon(Icons.edit_outlined, size: 20),
                                                    tooltip: 'Edit',
                                                    onPressed: () => openProductEditor(existing: prod as Map),
                                                  ),
                                                  IconButton(
                                                    icon: const Icon(Icons.delete_outline, size: 20, color: Colors.red),
                                                    tooltip: 'Delete',
                                                    onPressed: () async {
                                                      final confirm = await showDialog<bool>(
                                                        context: context,
                                                        builder: (ctx) => AlertDialog(
                                                          title: const Text('Delete product?'),
                                                          content: Text('Remove ${prod['name']} from your list?'),
                                                          actions: [
                                                            TextButton(
                                                              onPressed: () => Navigator.pop(ctx, false),
                                                              child: const Text('Cancel'),
                                                            ),
                                                            ElevatedButton(
                                                              style: ElevatedButton.styleFrom(
                                                                backgroundColor: Colors.red,
                                                                foregroundColor: Colors.white,
                                                              ),
                                                              onPressed: () => Navigator.pop(ctx, true),
                                                              child: const Text('Delete'),
                                                            ),
                                                          ],
                                                        ),
                                                      );
                                                      if (confirm != true) return;
                                                      await app.deleteExecutiveProduct(prod['id'].toString());
                                                      setModalState(() {});
                                                    },
                                                  ),
                                                  IconButton(
                                                    icon: const Icon(Icons.add_circle, color: BestieTokens.cBrand, size: 22),
                                                    tooltip: 'Add to order',
                                                    onPressed: () {
                                                      app.addProductToOrder(
                                                        prod['sku']?.toString() ?? 'SKU-GEN',
                                                        prod['name']?.toString() ?? 'Product',
                                                        1,
                                                        displayPrice,
                                                        productId: prod['id']?.toString(),
                                                        size: size,
                                                      );
                                                      setModalState(() {});
                                                    },
                                                  ),
                                                ],
                                              ),
                                            );
                                          },
                                        ),
                                ),
                                const Divider(height: 24),
                                const Text('Selected Products / Order Items:', style: TextStyle(fontWeight: FontWeight.bold)),
                                const SizedBox(height: 8),
                                if (app.currentOrderItems.isEmpty)
                                  const Padding(
                                    padding: EdgeInsets.symmetric(vertical: 8),
                                    child: Text(
                                      'No products selected. You can still submit remarks for follow-up tracking.',
                                      style: TextStyle(color: Colors.grey, fontStyle: FontStyle.italic, fontSize: 13),
                                    ),
                                  ),
                                ...app.currentOrderItems.map((item) {
                                  final unitP = double.tryParse(item['unitPrice']?.toString() ?? '') ?? 0.0;
                                  final qty = int.tryParse(item['qty']?.toString() ?? '') ?? 0;
                                  return Padding(
                                    padding: const EdgeInsets.symmetric(vertical: 4.0),
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Expanded(
                                          child: Text(item['name']?.toString() ?? 'Product', style: const TextStyle(fontSize: 13)),
                                        ),
                                        Row(
                                          children: [
                                            IconButton(
                                              icon: const Icon(Icons.remove_circle_outline, size: 20, color: Colors.red),
                                              onPressed: () {
                                                app.updateProductQty(item['sku'], qty - 1);
                                                setModalState(() {});
                                              },
                                            ),
                                            Text('$qty', style: const TextStyle(fontWeight: FontWeight.bold)),
                                            IconButton(
                                              icon: const Icon(Icons.add_circle_outline, size: 20, color: Colors.green),
                                              onPressed: () {
                                                app.updateProductQty(item['sku'], qty + 1);
                                                setModalState(() {});
                                              },
                                            ),
                                            const SizedBox(width: 8),
                                            Text(
                                              '₹${(unitP * qty).toStringAsFixed(2)}',
                                              style: const TextStyle(fontWeight: FontWeight.bold),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  );
                                }),
                                const Divider(height: 24),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    const Text('Order Grand Total:', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                                    Text(
                                      '₹${app.currentOrderTotal.toStringAsFixed(2)}',
                                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: BestieTokens.cBrand),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 16),
                                const Text('Quick Remarks:', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey)),
                                const SizedBox(height: 6),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 6,
                                  children: AppProvider.quickRemarkKeywords.map((remark) {
                                    final parts = remarksController.text
                                        .split(';')
                                        .map((e) => e.trim())
                                        .where((e) => e.isNotEmpty)
                                        .toList();
                                    final selected = parts.any(
                                      (p) => p.toLowerCase() == remark.toLowerCase(),
                                    );
                                    return ChoiceChip(
                                      label: Text(remark, style: const TextStyle(fontSize: 11)),
                                      selected: selected,
                                      onSelected: (_) {
                                        // Keep free-text notes; allow only one quick remark at a time.
                                        final custom = parts
                                            .where(
                                              (p) => !AppProvider.quickRemarkKeywords.any(
                                                (k) => k.toLowerCase() == p.toLowerCase(),
                                              ),
                                            )
                                            .toList();
                                        if (selected) {
                                          // Tap again to clear the quick remark.
                                          remarksController.text = custom.join('; ');
                                        } else {
                                          remarksController.text = [...custom, remark].join('; ');
                                        }
                                        remarksController.selection = TextSelection.collapsed(
                                          offset: remarksController.text.length,
                                        );
                                        setModalState(() {});
                                      },
                                    );
                                  }).toList(),
                                ),
                                const SizedBox(height: 12),
                                TextField(
                                  controller: remarksController,
                                  maxLines: 3,
                                  decoration: const InputDecoration(
                                    labelText: 'Visit Notes / Customer Remarks',
                                    hintText: 'Example: Customer asked to visit again next week. Payment pending.',
                                    border: OutlineInputBorder(),
                                    alignLabelWithHint: true,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        SafeArea(
                          top: false,
                          child: Padding(
                            padding: EdgeInsets.fromLTRB(16, 8, 16, safeBottom > 0 ? 8 : 16),
                            child: ElevatedButton(
                              onPressed: () async {
                                final hasProducts = app.currentOrderItems.isNotEmpty;
                                final hasRemarks = remarksController.text.trim().isNotEmpty;
                                if (!hasProducts && !hasRemarks) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('Add at least one product or a remark before submitting.'),
                                      backgroundColor: Colors.orange,
                                    ),
                                  );
                                  return;
                                }

                                final success = await app.submitOrder(remarksController.text.trim());
                                if (success && context.mounted) {
                                  Navigator.pop(context);
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('Visit products/remarks saved successfully!'),
                                      backgroundColor: Colors.green,
                                    ),
                                  );
                                }
                              },
                              child: const Text('SAVE PRODUCTS / REMARKS'),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            );
          },
        );
      },
    ).whenComplete(remarksController.dispose);
  }

  openSheet();
}

String _homeGreetingPrefix() {
  final hour = DateTime.now().hour;
  if (hour < 12) return 'Good morning';
  if (hour < 17) return 'Good afternoon';
  return 'Good evening';
}

class _HomeOutletsSection extends StatefulWidget {
  const _HomeOutletsSection({
    required this.onOpenOutlet,
    required this.onLongPressOutlet,
  });

  final void Function(Map<String, dynamic> outlet) onOpenOutlet;
  final void Function(Map<String, dynamic> outlet) onLongPressOutlet;

  @override
  State<_HomeOutletsSection> createState() => _HomeOutletsSectionState();
}

class _HomeOutletsSectionState extends State<_HomeOutletsSection> {
  int _section = 0; // 0 planned, 1 visited (remarks)
  String _remarkFilter = 'All';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<AppProvider>(context, listen: false).dedupePlannedOutlets();
    });
  }

  @override
  Widget build(BuildContext context) {
    final appProvider = Provider.of<AppProvider>(context);
    final list = _section == 0
        ? appProvider.pendingPlanOutlets
        : appProvider.visitedOutletsForRemark(_remarkFilter == 'All' ? null : _remarkFilter);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: SegmentedButton<int>(
            showSelectedIcon: false,
            style: const ButtonStyle(
              visualDensity: VisualDensity.compact,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            segments: [
              ButtonSegment(
                value: 0,
                label: Text('Planned (${appProvider.pendingPlanOutlets.length})', style: const TextStyle(fontSize: 11)),
                icon: const Icon(Icons.storefront, size: 14),
              ),
              ButtonSegment(
                value: 1,
                label: Text('Visited (${appProvider.visitedRemarkOutlets.length})', style: const TextStyle(fontSize: 11)),
                icon: const Icon(Icons.check_circle_outline, size: 14),
              ),
            ],
            selected: {_section},
            onSelectionChanged: (s) => setState(() {
              _section = s.first;
              if (_section == 0) _remarkFilter = 'All';
            }),
          ),
        ),
        if (_section == 1) ...[
          const SizedBox(height: 8),
          SizedBox(
            height: 36,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                'All',
                ...AppProvider.quickRemarkKeywords,
              ].map((label) {
                final selected = _remarkFilter == label;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: FilterChip(
                    label: Text(label, style: TextStyle(fontSize: 11, color: selected ? Colors.white : const Color(0xFF1D4ED8))),
                    selected: selected,
                    selectedColor: BestieTokens.cBrand,
                    backgroundColor: const Color(0xFFEFF6FF),
                    checkmarkColor: Colors.white,
                    onSelected: (_) => setState(() => _remarkFilter = label),
                    visualDensity: VisualDensity.compact,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                );
              }).toList(),
            ),
          ),
        ],
        const SizedBox(height: 8),
        if (list.isEmpty)
          Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              _section == 0
                  ? 'No planned outlets left. Add an outlet or open Visited.'
                  : _remarkFilter == 'All'
                      ? 'No visited outlets yet. After check-out with quick remarks they appear here.'
                      : 'No outlets tagged "$_remarkFilter" yet.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.grey),
            ),
          )
        else
          ...list.map((outlet) {
            final map = Map<String, dynamic>.from(outlet as Map);
            final isCompleted = map['visitStatus'] == 'COMPLETED';
            final isActiveHere = appProvider.isVisitActiveForOutlet(map['id']?.toString());
            final nextRaw = map['nextVisitDate']?.toString();
            final nextDt = nextRaw != null && nextRaw.isNotEmpty ? DateTime.tryParse(nextRaw)?.toLocal() : null;
            final nextLabel = nextDt != null ? DateFormat('dd MMM yyyy, hh:mm a').format(nextDt) : null;
            final chips = AppProvider.remarkChipsForOutlet(map);
            return Card(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              color: isCompleted
                  ? BestieTokens.cBrandSoft
                  : isActiveHere
                      ? const Color(0xFFEAF1FF)
                      : Colors.white,
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: BestieTokens.cBrand,
                  foregroundColor: Colors.white,
                  child: Icon(isCompleted
                      ? Icons.check
                      : isActiveHere
                          ? Icons.how_to_reg
                          : chips.isNotEmpty
                              ? Icons.label_outline
                              : Icons.store),
                ),
                title: Text(map['name']?.toString() ?? 'Outlet', style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      () {
                        final parts = <String>[];
                        if (isCompleted) {
                          parts.add('Visit completed');
                        } else if (isActiveHere) {
                          parts.add('Checked in — tap for remarks / checkout');
                        } else {
                          final addr = map['address']?.toString() ?? '';
                          if (addr.isNotEmpty) parts.add(addr);
                        }
                        final phone = map['phone']?.toString() ?? '';
                        if (phone.isNotEmpty) parts.add('Phone: $phone');
                        final owner = map['ownerName']?.toString() ?? '';
                        final ownerPhone = map['ownerPhone']?.toString() ?? '';
                        if (owner.isNotEmpty || ownerPhone.isNotEmpty) {
                          parts.add(
                            'Contact: ${owner.isEmpty ? '—' : owner}'
                            '${ownerPhone.isEmpty ? '' : ' · $ownerPhone'}',
                          );
                        }
                        return parts.isEmpty ? '' : parts.join('\n');
                      }(),
                    ),
                    if (chips.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: chips
                            .map(
                              (c) => Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFDBEAFE),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: const Color(0xFF93C5FD)),
                                ),
                                child: Text(
                                  c,
                                  style: const TextStyle(
                                    color: Color(0xFF1D4ED8),
                                    fontWeight: FontWeight.w700,
                                    fontSize: 11,
                                  ),
                                ),
                              ),
                            )
                            .toList(),
                      ),
                    ],
                    if (nextLabel != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        'Next visit: $nextLabel',
                        style: const TextStyle(
                          color: Color(0xFF1D4ED8),
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ],
                ),
                isThreeLine: true,
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: 'Outlet info',
                      icon: const Icon(Icons.info_outline, color: BestieTokens.cBrand),
                      onPressed: () => widget.onLongPressOutlet(map),
                    ),
                    Icon(
                      isCompleted
                          ? Icons.check_circle
                          : isActiveHere
                              ? Icons.edit_note
                              : Icons.arrow_forward_ios_outlined,
                      color: isCompleted || isActiveHere
                          ? BestieTokens.cBrand
                          : BestieTokens.cTextMuted,
                      size: 20,
                    ),
                  ],
                ),
                onTap: () => widget.onOpenOutlet(map),
                onLongPress: () => widget.onLongPressOutlet(map),
              ),
            );
          }),
      ],
    );
  }
}

class HomeTab extends StatelessWidget {
  const HomeTab({super.key});

  @override
  Widget build(BuildContext context) {
    final appProvider = Provider.of<AppProvider>(context);
    final isWorking = appProvider.attendanceStatus == 'LOGGED_IN' || appProvider.attendanceStatus == 'PRESENT';
    final hasCheckedOut = appProvider.attendanceCheckOutAt != null;

    final displayName = appProvider.email?.split('@').first ?? 'Executive';

    return SingleChildScrollView(
      padding: const EdgeInsets.only(bottom: 120),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(BestieTokens.s4, BestieTokens.s4, BestieTokens.s4, 0),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 22,
                  backgroundColor: BestieTokens.cBrandSoft,
                  child: Text(
                    displayName.substring(0, 1).toUpperCase(),
                    style: const TextStyle(color: BestieTokens.cBrandStrong, fontWeight: BestieTokens.fwBold),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_homeGreetingPrefix(), style: const TextStyle(color: BestieTokens.cTextMuted, fontSize: 12)),
                      Text(displayName, style: const TextStyle(fontSize: 20, fontWeight: BestieTokens.fwBold)),
                    ],
                  ),
                ),
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: isWorking ? BestieTokens.cBrand : BestieTokens.cTextFaint,
                    shape: BoxShape.circle,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: BestieTokens.s3),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: BestieTokens.s4),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(BestieTokens.rLg),
              child: Container(
                decoration: const BoxDecoration(gradient: BestieTokens.gBrand),
                child: Padding(
                  padding: const EdgeInsets.all(20.0),
                  child: Column(
                    children: [
                  Text(
                    isWorking
                        ? 'ACTIVE SESSION'
                        : hasCheckedOut
                            ? 'DAY COMPLETED'
                            : 'OFF DUTY',
                    style: const TextStyle(color: Colors.white70, fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    appProvider.hasCompletedLoginSelfieToday
                        ? 'Login selfie ✓ · GPS tracking on'
                        : 'Field login selfie once per day (at Sign in)',
                    style: TextStyle(
                      color: appProvider.hasCompletedLoginSelfieToday
                          ? Colors.white
                          : Colors.white70,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${appProvider.todayWorkingHours.toStringAsFixed(2)} Hours',
                    style: const TextStyle(color: Colors.white, fontSize: 36, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      Column(
                        children: [
                          const Text('Break Taken', style: TextStyle(color: Colors.white60, fontSize: 12)),
                          Text(appProvider.totalBreakFormatted, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                          if (appProvider.todayBreaks.isNotEmpty)
                            Text(
                              '${appProvider.todayBreaks.where((b) => b is Map && b['endTime'] != null).length} break(s)',
                              style: const TextStyle(color: Colors.white54, fontSize: 10),
                            ),
                        ],
                      ),
                      const SizedBox(height: 20, child: VerticalDivider(color: Colors.white24)),
                      Column(
                        children: [
                          const Text('Distance', style: TextStyle(color: Colors.white60, fontSize: 12)),
                          Text(
                            '${appProvider.totalDistanceCoveredKm.toStringAsFixed(2)} KM',
                            style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20, child: VerticalDivider(color: Colors.white24)),
                      Column(
                        children: [
                          const Text('Status', style: TextStyle(color: Colors.white60, fontSize: 12)),
                          Text(
                            appProvider.activeBreak != null
                                ? 'ON BREAK'
                                : isWorking
                                    ? 'WORKING'
                                    : hasCheckedOut
                                        ? 'CHECKED OUT'
                                        : 'ABSENT',
                            style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: _buildAttendanceTimeLabel(
                            'Check-in',
                            appProvider.attendanceCheckInAt == null ? 'Not checked in' : _formatAttendanceTime(appProvider.attendanceCheckInAt!),
                          ),
                        ),
                        const SizedBox(height: 32, child: VerticalDivider(color: Colors.white24)),
                        Expanded(
                          child: _buildAttendanceTimeLabel(
                            'Check-out',
                            appProvider.attendanceCheckOutAt != null
                                ? _formatAttendanceTime(appProvider.attendanceCheckOutAt!)
                                : isWorking
                                    ? 'Still working'
                                    : 'Not checked out',
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (isWorking) ...[
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: () => _confirmEndDay(context, appProvider),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: const BorderSide(color: Colors.white70),
                      ),
                      icon: const Icon(Icons.logout, size: 18),
                      label: const Text('END DAY / CHECK OUT'),
                    ),
                  ],
                    ],
                  ),
                ),
              ),
            ),
          ),

          // 2. Progress Bar (Module 4)
          Padding(
            padding: const EdgeInsets.fromLTRB(BestieTokens.s4, BestieTokens.s3, BestieTokens.s4, 0),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Today\'s Route Progress', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: BestieTokens.cBrand)),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Visits: ${appProvider.completedVisitsCount} / ${appProvider.plannedVisitsCount}'),
                        Text('${appProvider.totalDistanceCoveredKm.toStringAsFixed(2)} KM travelled'),
                      ],
                    ),
                    const SizedBox(height: 8),
                    LinearProgressIndicator(
                      value: appProvider.planProgressPercentage / 100.0,
                      minHeight: 12,
                      borderRadius: BorderRadius.circular(6),
                      backgroundColor: Colors.grey[200],
                      valueColor: const AlwaysStoppedAnimation<Color>(BestieTokens.cBrand),
                    ),
                  ],
                ),
              ),
            ),
          ),

          if (appProvider.todayPlan != null && appProvider.activeVisit == null)
            Padding(
              padding: const EdgeInsets.fromLTRB(BestieTokens.s4, BestieTokens.s3, BestieTokens.s4, 0),
              child: Card(
                color: BestieTokens.cBrandSoft,
                child: ListTile(
                  leading: const Icon(Icons.gps_fixed, color: BestieTokens.cBrand),
                  title: const Text('Auto visit monitoring active', style: TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text(
                    appProvider.selfieRequired
                        ? 'Stay within 100m for ${appProvider.minimumVisitDurationMinutes} min to start a visit. Selfie check-in is ON.'
                        : 'Stay within 100m for ${appProvider.minimumVisitDurationMinutes} min to auto-complete the outlet (selfie OFF).',
                  ),
                ),
              ),
            ),

          if (appProvider.activeVisit != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(BestieTokens.s4, BestieTokens.s3, BestieTokens.s4, 0),
              child: Card(
                color: BestieTokens.cBrandSoft,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text(
                        'ACTIVE OUTLET VISIT',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: BestieTokens.cBrand),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        appProvider.activeVisit!['outletName']?.toString() ??
                            (() {
                              final activeId = appProvider.activeVisit!['outletId']?.toString();
                              final match = appProvider.plannedOutlets.cast<dynamic>().firstWhere(
                                (o) => o is Map && o['id']?.toString() == activeId,
                                orElse: () => null,
                              );
                              if (match is Map) return match['name']?.toString() ?? 'Checked-in outlet';
                              return 'Checked-in outlet';
                            })(),
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Checked in — add remarks/order or check out when done.',
                        style: TextStyle(fontSize: 12, color: Colors.black54),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton.icon(
                              icon: const Icon(Icons.edit_note, size: 18),
                              label: const Text('Remarks / Order'),
                              onPressed: () => showOrderCatalogScreen(context, appProvider),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: BestieTokens.cBrand,
                                foregroundColor: Colors.white,
                              ),
                              icon: const Icon(Icons.logout, size: 18),
                              label: const Text('Check-out'),
                              onPressed: () async {
                                final ok = await appProvider.checkoutOutlet();
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(ok ? 'Checked out successfully.' : 'Checkout failed.'),
                                      backgroundColor: ok ? Colors.green : Colors.red,
                                    ),
                                  );
                                }
                              },
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),

          // 3. Daily Area Selector (If no plan active, Module 4)
          if (appProvider.todayPlan == null)
            Padding(
              padding: const EdgeInsets.fromLTRB(BestieTokens.s4, BestieTokens.s3, BestieTokens.s4, 0),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Configure Your Day', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: BestieTokens.cBrand)),
                      const SizedBox(height: 8),
                      const Text('Choose an assigned route territory to load your target outlets checklist.'),
                      const SizedBox(height: 16),
                      ElevatedButton.icon(
                        icon: const Icon(Icons.add_road),
                        label: const Text('SELECT TODAY\'S ROUTE AREA'),
                        onPressed: () {
                          _showAreaPlanningSheet(context, appProvider);
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ),

          // Outlets: Planned / Visited / Saved
          Padding(
            padding: const EdgeInsets.only(left: 16, top: 16, right: 16, bottom: 8),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'OUTLETS',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.grey),
                  ),
                ),
                if (appProvider.todayPlan != null)
                  TextButton.icon(
                    icon: const Icon(Icons.add_business, size: 18),
                    label: const Text('ADD OUTLET'),
                    onPressed: () => _showAddManualOutletSheet(context, appProvider),
                  ),
              ],
            ),
          ),
          _HomeOutletsSection(
            onOpenOutlet: (outlet) => _showOutletWorkflowDialog(context, appProvider, outlet),
            onLongPressOutlet: (outlet) => _showOutletLongPressActions(context, appProvider, outlet),
          ),
        ],
      ),
    );
  }

  Widget _buildAttendanceTimeLabel(String label, String value) {
    return Column(
      children: [
        Text(label, style: const TextStyle(color: Colors.white60, fontSize: 11, fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        Text(
          value,
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700),
        ),
      ],
    );
  }

  String _formatAttendanceTime(DateTime dateTime) {
    return DateFormat('hh:mm a').format(dateTime.toLocal());
  }

  void _confirmEndDay(BuildContext context, AppProvider provider) {
    showDialog(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('End your work day?'),
          content: const Text(
            'This records your check-out time for today. You can still stay logged in to review visits, but your working hours timer will stop.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('CANCEL'),
            ),
            ElevatedButton(
              onPressed: () async {
                final success = await provider.checkOutAttendance();
                if (dialogContext.mounted) Navigator.pop(dialogContext);
                if (success && context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        'Day checked out at ${DateFormat('hh:mm a').format(DateTime.now())}.',
                      ),
                      backgroundColor: Colors.green,
                    ),
                  );
                }
              },
              child: const Text('END DAY'),
            ),
          ],
        );
      },
    );
  }

  void _showAreaPlanningSheet(BuildContext context, AppProvider provider) async {
    await provider.fetchAvailableRoutes();
    if (!context.mounted) return;

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Select Planned Territory Route',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: BestieTokens.cBrand),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                icon: const Icon(Icons.add_location_alt_outlined),
                label: const Text('ADD CUSTOM ROUTE / AREA'),
                onPressed: () {
                  Navigator.pop(context);
                  _showAddManualRouteSheet(context, provider);
                },
              ),
              const Divider(height: 24),
              if (provider.availableRoutes.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 20.0),
                  child: Text(
                    'No route areas saved yet. Add a custom route/area to start today\'s plan.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey),
                  ),
                ),
              ...provider.availableRoutes.map((route) {
                final outlets = route['outlets'] as List<dynamic>? ?? [];
                return ListTile(
                  leading: const Icon(Icons.map, color: BestieTokens.cBrand),
                  title: Text(route['name']),
                  subtitle: Text('Region: ${route['region']} • Outlets: ${outlets.length}'),
                  onTap: () async {
                    Navigator.pop(context);
                    await provider.saveDailyPlan(route['id'], route['name'], outlets.length);
                  },
                );
              }),
            ],
          ),
        );
      },
    );
  }

  void _showAddManualRouteSheet(BuildContext context, AppProvider provider) {
    final routeNameController = TextEditingController();
    final regionController = TextEditingController();
    final outletNameController = TextEditingController();
    final outletAddressController = TextEditingController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom + 24,
            left: 20,
            right: 20,
            top: 24,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Add Custom Route / Area',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: BestieTokens.cBrand),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: routeNameController,
                  decoration: const InputDecoration(
                    labelText: 'Route / Area Name',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.map_outlined),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: regionController,
                  decoration: const InputDecoration(
                    labelText: 'Region / City',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.location_city),
                  ),
                ),
                const SizedBox(height: 16),
                const Text('Optional first outlet', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
                const SizedBox(height: 8),
                TextField(
                  controller: outletNameController,
                  decoration: const InputDecoration(
                    labelText: 'Outlet Name',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.storefront),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: outletAddressController,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'Outlet Address',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.place),
                  ),
                ),
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  icon: const Icon(Icons.save),
                  label: const Text('SAVE CUSTOM ROUTE'),
                  onPressed: () async {
                    final routeName = routeNameController.text.trim();
                    final region = regionController.text.trim();
                    if (routeName.isEmpty || region.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Route name and region are required.'), backgroundColor: Colors.red),
                      );
                      return;
                    }

                    final manualOutlets = <Map<String, dynamic>>[];
                    final outletName = outletNameController.text.trim();
                    final outletAddress = outletAddressController.text.trim();
                    if (outletName.isNotEmpty || outletAddress.isNotEmpty) {
                      if (outletName.isEmpty || outletAddress.isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('First outlet requires both name and address.'), backgroundColor: Colors.red),
                        );
                        return;
                      }
                      final targetLocation = await _resolveOutletTargetLocation(outletAddress);
                      if (targetLocation == null) {
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Could not get this outlet location. Turn on GPS or enter a better address.'), backgroundColor: Colors.red),
                        );
                        return;
                      }
                      manualOutlets.add({
                        'id': 'outlet-manual-${DateTime.now().millisecondsSinceEpoch}',
                        'name': outletName,
                        'address': outletAddress,
                        'latitude': targetLocation.latitude,
                        'longitude': targetLocation.longitude,
                        'grade': 'Unrated',
                        'overallRating': null,
                        'visitStatus': 'PENDING',
                        'isManual': true,
                      });
                    }

                    await provider.createManualRoute(routeName, region, outlets: manualOutlets);
                    if (!context.mounted) return;
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Custom route added. Select it from route list.'), backgroundColor: Colors.green),
                    );
                    _showAreaPlanningSheet(context, provider);
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showAddManualOutletSheet(BuildContext context, AppProvider provider) {
    final nameController = TextEditingController();
    final addressController = TextEditingController();
    final phoneController = TextEditingController();
    final ownerNameController = TextEditingController();
    final ownerPhoneController = TextEditingController();
    latlong.LatLng? pinnedLocation;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom + 24,
                left: 20,
                right: 20,
                top: 24,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'Add Outlet to Today\'s Plan',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: BestieTokens.cBrand),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: nameController,
                      decoration: const InputDecoration(
                        labelText: 'Outlet name',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.storefront),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: phoneController,
                      keyboardType: TextInputType.phone,
                      decoration: const InputDecoration(
                        labelText: 'Outlet phone number',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.phone),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: ownerNameController,
                      decoration: const InputDecoration(
                        labelText: 'Concern person name',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.person_outline),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: ownerPhoneController,
                      keyboardType: TextInputType.phone,
                      decoration: const InputDecoration(
                        labelText: 'Concern person phone',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.contact_phone_outlined),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: addressController,
                      maxLines: 2,
                      decoration: const InputDecoration(
                        labelText: 'Outlet address',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.place),
                      ),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      icon: Icon(
                        pinnedLocation == null ? Icons.add_location_alt_outlined : Icons.edit_location_alt,
                      ),
                      label: Text(
                        pinnedLocation == null
                            ? 'PIN LOCATION ON MAP'
                            : 'PIN SET (${pinnedLocation!.latitude.toStringAsFixed(5)}, ${pinnedLocation!.longitude.toStringAsFixed(5)}) — TAP TO CHANGE',
                      ),
                      onPressed: () async {
                        final picked = await OutletLocationPinPicker.open(context, initial: pinnedLocation);
                        if (picked != null) {
                          setSheetState(() => pinnedLocation = picked);
                        }
                      },
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Pin on the map, or type an address inside the pin screen so the pin moves to that place.',
                      style: TextStyle(fontSize: 11, color: Colors.grey),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton.icon(
                      icon: const Icon(Icons.add_business),
                      label: const Text('ADD OUTLET'),
                      onPressed: () async {
                        final name = nameController.text.trim();
                        final address = addressController.text.trim();
                        final phone = phoneController.text.trim();
                        final ownerName = ownerNameController.text.trim();
                        final ownerPhone = ownerPhoneController.text.trim();
                        if (name.isEmpty || address.isEmpty) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Outlet name and address are required.'), backgroundColor: Colors.red),
                          );
                          return;
                        }
                        if (phone.isEmpty || ownerName.isEmpty || ownerPhone.isEmpty) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Outlet phone, concern person name and phone are required.'),
                              backgroundColor: Colors.red,
                            ),
                          );
                          return;
                        }
                        if (pinnedLocation == null) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Pin the outlet location on the map first.'), backgroundColor: Colors.orange),
                          );
                          return;
                        }

                        await provider.addManualOutletToTodayPlan(
                          name,
                          address,
                          latitude: pinnedLocation!.latitude,
                          longitude: pinnedLocation!.longitude,
                          phone: phone,
                          ownerName: ownerName,
                          ownerPhone: ownerPhone,
                        );
                        if (!context.mounted) return;
                        Navigator.pop(context);
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Outlet added to today\'s target list.'), backgroundColor: Colors.green),
                        );
                      },
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _showOutletLongPressActions(
    BuildContext context,
    AppProvider provider,
    Map<String, dynamic> outlet,
  ) {
    final name = outlet['name']?.toString() ?? 'Outlet';
    final phone = outlet['phone']?.toString() ?? '';
    final owner = outlet['ownerName']?.toString() ?? '';
    final ownerPhone = outlet['ownerPhone']?.toString() ?? '';
    final address = outlet['address']?.toString() ?? '';
    final nextRaw = outlet['nextVisitDate']?.toString();
    final nextDt = nextRaw != null && nextRaw.isNotEmpty ? DateTime.tryParse(nextRaw)?.toLocal() : null;
    final nextLabel = nextDt != null ? DateFormat('dd MMM yyyy, hh:mm a').format(nextDt) : null;
    final nextNotes = (outlet['nextVisitNotes']?.toString() ?? '').trim();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: Column(
                    children: [
                      Text(
                        name,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Long-press menu',
                        style: TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                    ],
                  ),
                ),
                // Summary of entered details
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Card(
                    color: BestieTokens.cBrandSoft,
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Outlet details', style: TextStyle(fontWeight: FontWeight.w700)),
                          const SizedBox(height: 6),
                          Text('Name: $name'),
                          Text('Phone: ${phone.isEmpty ? '—' : phone}'),
                          Text('Concern person: ${owner.isEmpty ? '—' : owner}'),
                          Text('Concern phone: ${ownerPhone.isEmpty ? '—' : ownerPhone}'),
                          Text('Address: ${address.isEmpty ? '—' : address}'),
                          if (nextLabel != null) ...[
                            const SizedBox(height: 4),
                            Text('Next visit: $nextLabel', style: const TextStyle(fontWeight: FontWeight.w600, color: Color(0xFF1D4ED8))),
                            if (nextNotes.isNotEmpty) Text('Notes: $nextNotes'),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                ListTile(
                  leading: const Icon(Icons.info_outline, color: BestieTokens.cBrand),
                  title: const Text('View full info'),
                  subtitle: const Text('All details entered for this outlet'),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    _showOutletInfoDialog(context, outlet);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.event_available, color: BestieTokens.cBrand),
                  title: const Text('Save for next visit'),
                  subtitle: Text(nextLabel == null ? 'Pick date, time and notes' : 'Scheduled: $nextLabel'),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    _showScheduleNextVisitDialog(context, provider, outlet);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.delete_outline, color: Colors.red),
                  title: const Text('Delete outlet'),
                  subtitle: const Text('Remove from your plan'),
                  onTap: () async {
                    Navigator.pop(sheetContext);
                    final confirm = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: const Text('Delete outlet?'),
                        content: Text('Remove "$name" from your list?'),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
                            onPressed: () => Navigator.pop(ctx, true),
                            child: const Text('Delete'),
                          ),
                        ],
                      ),
                    );
                    if (confirm != true || !context.mounted) return;
                    final ok = await provider.deletePlannedOutlet(outlet['id']?.toString() ?? '');
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(ok ? 'Outlet deleted.' : (provider.lastActionError ?? 'Delete failed.')),
                        backgroundColor: ok ? Colors.green : Colors.red,
                      ),
                    );
                  },
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showOutletInfoDialog(BuildContext context, Map<String, dynamic> outlet) {
    final name = outlet['name']?.toString() ?? 'Outlet';
    final phone = outlet['phone']?.toString() ?? '';
    final owner = outlet['ownerName']?.toString() ?? '';
    final ownerPhone = outlet['ownerPhone']?.toString() ?? '';
    final address = outlet['address']?.toString() ?? '';
    final lat = outlet['latitude']?.toString() ?? '';
    final lng = outlet['longitude']?.toString() ?? '';
    final nextRaw = outlet['nextVisitDate']?.toString();
    final nextDt = nextRaw != null && nextRaw.isNotEmpty ? DateTime.tryParse(nextRaw)?.toLocal() : null;
    final nextLabel = nextDt != null ? DateFormat('dd MMM yyyy, hh:mm a').format(nextDt) : null;
    final nextNotes = (outlet['nextVisitNotes']?.toString() ?? '').trim();

    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Outlet information'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _infoRow('Outlet name', name),
              _infoRow('Outlet phone', phone.isEmpty ? '—' : phone),
              _infoRow('Concern person', owner.isEmpty ? '—' : owner),
              _infoRow('Concern phone', ownerPhone.isEmpty ? '—' : ownerPhone),
              _infoRow('Address', address.isEmpty ? '—' : address),
              if (lat.isNotEmpty && lng.isNotEmpty) _infoRow('Location pin', '$lat, $lng'),
              _infoRow('Next visit', nextLabel ?? 'Not scheduled'),
              if (nextNotes.isNotEmpty) _infoRow('Next visit notes', nextNotes),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
        ],
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey, fontWeight: FontWeight.w600)),
          const SizedBox(height: 2),
          Text(value, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  Future<void> _showScheduleNextVisitDialog(
    BuildContext context,
    AppProvider provider,
    Map<String, dynamic> outlet,
  ) async {
    DateTime when = DateTime.now().add(const Duration(days: 1));
    final existing = DateTime.tryParse(outlet['nextVisitDate']?.toString() ?? '');
    if (existing != null) when = existing.toLocal();
    final notesCtrl = TextEditingController(text: outlet['nextVisitNotes']?.toString() ?? '');

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            return AlertDialog(
              title: const Text('Save for next visit'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(outlet['name']?.toString() ?? 'Outlet', style: const TextStyle(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 12),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Date'),
                      subtitle: Text(DateFormat('dd MMM yyyy').format(when)),
                      trailing: const Icon(Icons.calendar_today),
                      onTap: () async {
                        final picked = await showDatePicker(
                          context: ctx,
                          initialDate: when,
                          firstDate: DateTime.now().subtract(const Duration(days: 1)),
                          lastDate: DateTime.now().add(const Duration(days: 365)),
                        );
                        if (picked != null) {
                          setLocal(() {
                            when = DateTime(picked.year, picked.month, picked.day, when.hour, when.minute);
                          });
                        }
                      },
                    ),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Time'),
                      subtitle: Text(DateFormat('hh:mm a').format(when)),
                      trailing: const Icon(Icons.access_time),
                      onTap: () async {
                        final picked = await showTimePicker(
                          context: ctx,
                          initialTime: TimeOfDay.fromDateTime(when),
                        );
                        if (picked != null) {
                          setLocal(() {
                            when = DateTime(when.year, when.month, when.day, picked.hour, picked.minute);
                          });
                        }
                      },
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: notesCtrl,
                      maxLines: 3,
                      decoration: const InputDecoration(
                        labelText: 'Notes / relevant info',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save')),
              ],
            );
          },
        );
      },
    );

    if (saved != true || !context.mounted) return;
    final ok = await provider.scheduleOutletNextVisit(
      outletId: outlet['id']?.toString() ?? '',
      when: when,
      notes: notesCtrl.text,
    );
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          ok
              ? 'Next visit saved for ${DateFormat('dd MMM yyyy, hh:mm a').format(when)}.'
              : (provider.lastActionError ?? 'Could not save next visit.'),
        ),
        backgroundColor: ok ? Colors.green : Colors.red,
      ),
    );
  }

  void _showOutletWorkflowDialog(BuildContext context, AppProvider provider, Map<String, dynamic> outlet) async {
    await provider.restoreActiveVisitForOutlet(outlet['id']?.toString() ?? '');
    await provider.restoreActiveVisitFromLocalDb();
    if (!context.mounted) return;

    showDialog(
      context: context,
      builder: (context) {
        final latestProvider = Provider.of<AppProvider>(context);
        final isCompleted = outlet['visitStatus'] == 'COMPLETED' ||
            latestProvider.plannedOutlets.cast<dynamic>().any(
              (o) => o is Map &&
                  o['id']?.toString() == outlet['id']?.toString() &&
                  o['visitStatus'] == 'COMPLETED',
            );
        final activeVisit = latestProvider.activeVisit;
        final isThisOutletActive = latestProvider.isVisitActiveForOutlet(outlet['id']?.toString());
        final hasOtherActiveVisit = activeVisit != null && !isThisOutletActive;

        return AlertDialog(
          title: Text(outlet['name']),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Address: ${outlet['address']}'),
              const SizedBox(height: 8),
              Text('Grade: ${outlet['grade'] ?? "Unrated"} | Rating: ${outlet['overallRating'] ?? "None"}'),
              const SizedBox(height: 12),
              FutureBuilder<List<Map<String, dynamic>>>(
                future: latestProvider.getOutletVisitHistory(outlet['id']?.toString() ?? ''),
                builder: (context, snapshot) {
                  final history = snapshot.data ?? [];
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Text('Loading previous visit history...', style: TextStyle(fontSize: 12, color: Colors.grey));
                  }
                  if (history.isEmpty) {
                    return const Text('No previous remarks/products recorded for this outlet yet.', style: TextStyle(fontSize: 12, color: Colors.grey));
                  }

                  final latest = history.first;
                  final products = latest['products'] as List<dynamic>? ?? [];
                  final productText = products.isEmpty
                      ? 'No products recorded'
                      : products.map((p) => '${p['name'] ?? p['sku'] ?? 'Product'} x${p['qty'] ?? 0}').join(', ');

                  return Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.blueGrey[50],
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('LAST CUSTOMER DISCUSSION', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey)),
                        const SizedBox(height: 4),
                        Text(latest['remarks']?.toString().isNotEmpty == true ? latest['remarks'] : 'No remarks added.'),
                        const SizedBox(height: 6),
                        Text('Products: $productText', style: const TextStyle(fontSize: 12, color: BestieTokens.cBrand)),
                      ],
                    ),
                  );
                },
              ),
              const SizedBox(height: 16),
              if (!isCompleted && activeVisit == null)
                const Text('To start the visit checklist, you must first check in at the outlet.'),
              if (isThisOutletActive)
                const Text('You are checked in here. Add remarks/order or check out when finished.'),
              if (hasOtherActiveVisit)
                const Text('Another outlet visit is currently active. Check out from the active visit banner on Home, or force check-out below.'),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('CLOSE'),
            ),
            if (hasOtherActiveVisit)
              TextButton(
                onPressed: () async {
                  await latestProvider.forceCheckoutActiveVisit();
                  if (context.mounted) Navigator.pop(context);
                },
                child: const Text('FORCE CHECK-OUT'),
              ),
            if (!isCompleted && activeVisit == null)
              ElevatedButton.icon(
                icon: const Icon(Icons.gps_fixed),
                label: const Text('CHECK-IN (100M GEOFENCE)'),
                onPressed: () async {
                  Navigator.pop(context);
                  _runCheckInFlow(context, latestProvider, outlet);
                },
              ),
            if (isThisOutletActive) ...[
              ElevatedButton.icon(
                icon: const Icon(Icons.add_shopping_cart),
                label: const Text('ORDER / REMARKS'),
                onPressed: () {
                  Navigator.pop(context);
                  showOrderCatalogScreen(context, latestProvider);
                },
              ),
              ElevatedButton.icon(
                icon: const Icon(Icons.directions_walk),
                label: const Text('CHECK-OUT'),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
                onPressed: () async {
                  await latestProvider.checkoutOutlet();
                  if (context.mounted) Navigator.pop(context);
                },
              ),
            ]
          ],
        );
      },
    );
  }

  void _runCheckInFlow(BuildContext context, AppProvider provider, Map<String, dynamic> outlet) async {
    // 1. Fetch GPS location (always required for geofence)
    double executiveLat;
    double executiveLng;
    String executiveAddress;

    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Turn on Location Services. GPS is required for outlet check-in.'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Location permission is required for outlet check-in.'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.bestForNavigation,
          timeLimit: Duration(seconds: 15),
        ),
      );
      executiveLat = position.latitude;
      executiveLng = position.longitude;
      executiveAddress = await _resolveAddress(executiveLat, executiveLng);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Unable to get accurate GPS location: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    // 2. Selfie only when admin policy requires it (default: No)
    // Blink-gated liveness: photo is taken only after an eye blink is detected.
    String selfiePath = 'auto-detected';
    if (provider.selfieRequired) {
      if (!context.mounted) return;
      File? photo;
      try {
        photo = await BlinkSelfieCaptureScreen.open(
          context,
          title: 'Check-in selfie — blink to capture',
        );
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to access camera: $e'), backgroundColor: Colors.red),
          );
        }
        return;
      }

      if (photo == null) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Selfie required — blink your eyes in front of the camera to capture.'),
              backgroundColor: Colors.orange,
            ),
          );
        }
        return;
      }
      selfiePath = photo.path;
    }

    final result = await provider.checkInOutlet(
      outlet['id'],
      executiveLat,
      executiveLng,
      selfiePath,
      address: executiveAddress,
    );

    if (context.mounted && result != null) {
      if (result['requiresOutletLocation'] == true) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(result['message'] ?? 'Outlet target location is required.'), backgroundColor: Colors.red),
        );
      } else if (result['requiresOverride'] == true) {
        _showGeofenceOverrideDialog(
          context,
          provider,
          outlet,
          result['distanceMeters'] ?? 0.0,
          selfiePath,
          executiveLat,
          executiveLng,
          executiveAddress,
        );
      } else if (result['success'] == true && result['visit'] != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              provider.selfieRequired
                  ? 'Checked in with GPS & selfie. Visit is active.'
                  : 'Checked in with GPS. Visit is active.',
            ),
            backgroundColor: Colors.green,
          ),
        );
        showActiveVisitActionsDialog(context, provider, outlet);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result['message'] ?? 'Check-in was not completed. Please try again.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<String> _resolveAddress(double latitude, double longitude) async {
    try {
      final places = await placemarkFromCoordinates(latitude, longitude);
      if (places.isNotEmpty) {
        final p = places.first;
        final addressParts = [
          p.name,
          p.street,
          p.subLocality,
          p.locality,
          p.subAdministrativeArea,
          p.administrativeArea,
          p.postalCode,
          p.country,
        ].where((v) => v != null && v.trim().isNotEmpty).map((v) => v!.trim()).toList();

        final deduped = <String>[];
        for (final part in addressParts) {
          if (!deduped.contains(part)) deduped.add(part);
        }
        if (deduped.isNotEmpty) return deduped.join(', ');
      }
    } catch (_) {
      // Fall back to coordinates if reverse geocoding fails.
    }
    return '${latitude.toStringAsFixed(6)}, ${longitude.toStringAsFixed(6)}';
  }

  Future<Location?> _resolveTargetCoordinates(String address) async {
    try {
      final locations = await locationFromAddress(address);
      if (locations.isNotEmpty) return locations.first;
    } catch (_) {
      // The caller shows a validation message.
    }
    return null;
  }

  Future<Location?> _resolveOutletTargetLocation(
    String address, {
    double? manualLat,
    double? manualLng,
  }) async {
    if (manualLat != null && manualLng != null) {
      return Location(latitude: manualLat, longitude: manualLng, timestamp: DateTime.now());
    }

    final resolved = await _resolveTargetCoordinates(address);
    if (resolved != null) return resolved;

    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return null;

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
        return null;
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.bestForNavigation,
          timeLimit: Duration(seconds: 15),
        ),
      );
      return Location(latitude: position.latitude, longitude: position.longitude, timestamp: DateTime.now());
    } catch (_) {
      return null;
    }
  }

  void _showGeofenceOverrideDialog(BuildContext context, AppProvider provider, Map<String, dynamic> outlet, double distance, String selfiePath, double accurateLat, double accurateLng, String accurateAddress) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Geofence Violation'),
          content: Text('Warning: You are too far from this outlet. Current distance is ${distance.toStringAsFixed(1)}m. Configured limit is 100m. Would you like to request a manager approval override?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('CANCEL'),
            ),
            ElevatedButton(
              onPressed: () async {
                Navigator.pop(context);
                final result = await provider.checkInOutlet(
                  outlet['id'],
                  accurateLat,
                  accurateLng,
                  selfiePath,
                  managerOverride: true,
                  address: accurateAddress,
                );
                if (context.mounted) {
                  if (result?['success'] == true && result?['visit'] != null) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Geofence warning bypassed with Manager Override flag.'), backgroundColor: Colors.orange),
                    );
                    showActiveVisitActionsDialog(context, provider, outlet);
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(result?['message'] ?? 'Check-in override failed.'), backgroundColor: Colors.red),
                    );
                  }
                }
              },
              child: const Text('REQUEST OVERRIDE'),
            ),
          ],
        );
      },
    );
  }
}

// ---------------- MAP & TRACKING TAB ----------------
/// Stable map surface — avoids tearing/crash when parent rebuilds during pinch-zoom.
class _StableRouteMap extends StatefulWidget {
  const _StableRouteMap({
    super.key,
    required this.mapController,
    required this.positionListenable,
    required this.initialCenter,
    required this.directionPoints,
    required this.onMapReady,
    required this.onFatalError,
  });

  final MapController mapController;
  final ValueNotifier<latlong.LatLng?> positionListenable;
  final latlong.LatLng initialCenter;
  final List<latlong.LatLng> directionPoints;
  final VoidCallback onMapReady;
  final VoidCallback onFatalError;

  @override
  State<_StableRouteMap> createState() => _StableRouteMapState();
}

class _StableRouteMapState extends State<_StableRouteMap> {
  late latlong.LatLng _center;
  bool _readyNotified = false;
  List<latlong.LatLng> _line = const [];

  @override
  void initState() {
    super.initState();
    _center = widget.initialCenter;
    _line = widget.directionPoints;
  }

  @override
  void didUpdateWidget(covariant _StableRouteMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Update polyline data without resetting the camera / recreating map options.
    if (!listEquals(_line, widget.directionPoints)) {
      setState(() => _line = List<latlong.LatLng>.from(widget.directionPoints));
    }
  }

  @override
  Widget build(BuildContext context) {
    try {
      return FlutterMap(
        mapController: widget.mapController,
        options: MapOptions(
          initialCenter: _center,
          initialZoom: 13,
          minZoom: 3,
          maxZoom: 18,
          backgroundColor: const Color(0xFFE8EEF4),
          interactionOptions: const InteractionOptions(
            flags: InteractiveFlag.all,
          ),
          onMapReady: () {
            if (_readyNotified) return;
            _readyNotified = true;
            widget.onMapReady();
          },
        ),
        children: [
          TileLayer(
            urlTemplate: 'https://basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}.png',
            userAgentPackageName: 'com.fieldforce.mobile',
            maxZoom: 19,
            maxNativeZoom: 18,
            keepBuffer: 2,
            panBuffer: 1,
            retinaMode: false,
            errorTileCallback: (tile, error, stackTrace) {},
          ),
          if (_line.length >= 2)
            PolylineLayer(
              polylines: [
                Polyline(
                  points: _line,
                  color: BestieTokens.cBrand,
                  strokeWidth: 4.5,
                  borderStrokeWidth: 1.5,
                  borderColor: Colors.white,
                ),
              ],
            ),
          ValueListenableBuilder<latlong.LatLng?>(
            valueListenable: widget.positionListenable,
            builder: (context, pos, _) {
              if (pos == null) return const SizedBox.shrink();
              if (pos.latitude.abs() < 0.01 && pos.longitude.abs() < 0.01) {
                return const SizedBox.shrink();
              }
              return MarkerLayer(
                markers: [
                  Marker(
                    point: pos,
                    width: 44,
                    height: 44,
                    child: const Icon(Icons.my_location, color: Colors.blue, size: 34),
                  ),
                ],
              );
            },
          ),
        ],
      );
    } catch (e, st) {
      debugPrint('Route map build failed: $e\n$st');
      WidgetsBinding.instance.addPostFrameCallback((_) => widget.onFatalError());
      return const ColoredBox(
        color: Color(0xFFE8EEF4),
        child: Center(child: Text('Reloading map…')),
      );
    }
  }
}

class MapTrackingTab extends StatefulWidget {
  const MapTrackingTab({super.key});

  @override
  State<MapTrackingTab> createState() => _MapTrackingTabState();
}

class _MapTrackingTabState extends State<MapTrackingTab>
    with AutomaticKeepAliveClientMixin {
  latlong.LatLng? _currentPosition;
  final ValueNotifier<latlong.LatLng?> _positionListenable = ValueNotifier(null);
  final MapController _mapController = MapController();
  bool _mapReady = false;
  bool _mapFailed = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    // Show map immediately; GPS can update the center later (don't block tiles).
    _loadCurrentPosition();
  }

  @override
  void dispose() {
    _positionListenable.dispose();
    // Do not dispose MapController here — IndexedStack/KeepAlive can still
    // hold FlutterMap briefly and disposing mid-gesture crashes the map.
    super.dispose();
  }

  Future<void> _loadCurrentPosition() async {
    try {
      final position = await DeviceLocation.resolvePosition(timeLimit: const Duration(seconds: 6));
      if (!mounted || position == null) return;
      final next = latlong.LatLng(position.latitude, position.longitude);
      _currentPosition = next;
      _positionListenable.value = next;
      if (_mapReady) {
        try {
          final z = _mapController.camera.zoom;
          _mapController.move(next, z.isFinite ? z.clamp(4, 18) : 15);
        } catch (_) {}
      }
    } catch (_) {
      // Keep map usable even if current location is unavailable.
    }
  }

  void _nudgeMapPaint(AppProvider provider) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_mapReady || _mapFailed) return;
      try {
        final points = _buildOutletPoints(provider);
        if (points.isNotEmpty) {
          _fitMapToPoints(points);
        } else if (_currentPosition != null) {
          _mapController.move(_currentPosition!, 15);
        } else {
          final center = _initialMapTarget(provider);
          _mapController.move(center, 12);
        }
      } catch (_) {}
    });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // AutomaticKeepAliveClientMixin
    // Select only stats so map child is not rebuilt on every GPS ping.
    final distanceKm = context.select<AppProvider, double>((p) => p.totalDistanceCoveredKm);
    final completed = context.select<AppProvider, int>((p) => p.completedVisitsCount);
    final planned = context.select<AppProvider, int>((p) => p.plannedVisitsCount);
    final routeTick = context.select<AppProvider, int>((p) {
      final opt = p.optimizedRoute;
      if (opt == null) return 0;
      final seq = opt['stopSequence'];
      return seq is List ? seq.length : opt.hashCode;
    });
    final appProvider = Provider.of<AppProvider>(context, listen: false);
    // Touch routeTick so analyzer knows the select is intentional (rebuild on optimize).
    final directionPoints = routeTick >= 0 ? _safeDirectionPoints(appProvider) : const <latlong.LatLng>[];

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  Column(
                    children: [
                      const Text('Total Distance', style: TextStyle(color: Colors.grey)),
                      Text(
                        '${distanceKm.toStringAsFixed(2)} KM',
                        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: BestieTokens.cBrand),
                      ),
                    ],
                  ),
                  const SizedBox(height: 40, child: VerticalDivider()),
                  Column(
                    children: [
                      const Text('Visits today', style: TextStyle(color: Colors.grey)),
                      Text(
                        '$completed/$planned',
                        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: BestieTokens.cBrand),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: ColoredBox(
                color: const Color(0xFFE8EEF4),
                child: _mapFailed
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text('Map hiccup — tap to reload', style: TextStyle(color: Colors.black54)),
                            const SizedBox(height: 10),
                            ElevatedButton(
                              onPressed: () {
                                setState(() {
                                  _mapFailed = false;
                                  _mapReady = false;
                                });
                              },
                              child: const Text('Reload map'),
                            ),
                          ],
                        ),
                      )
                    : Stack(
                        children: [
                          _StableRouteMap(
                            key: const ValueKey('stable_route_map'),
                            mapController: _mapController,
                            positionListenable: _positionListenable,
                            initialCenter: _initialMapTarget(appProvider),
                            directionPoints: directionPoints,
                            onMapReady: () {
                              if (!mounted) return;
                              setState(() => _mapReady = true);
                              _nudgeMapPaint(appProvider);
                              Future<void>.delayed(const Duration(milliseconds: 120), () {
                                if (mounted) _nudgeMapPaint(appProvider);
                              });
                            },
                            onFatalError: () {
                              if (mounted) setState(() => _mapFailed = true);
                            },
                          ),
                          if (!_mapReady)
                            const Positioned.fill(
                              child: Center(
                                child: SizedBox(
                                  width: 28,
                                  height: 28,
                                  child: CircularProgressIndicator(strokeWidth: 2.5),
                                ),
                              ),
                            ),
                          Positioned(
                            right: 12,
                            bottom: 12,
                            child: FloatingActionButton.small(
                              heroTag: 'route-map-location',
                              backgroundColor: Colors.white,
                              foregroundColor: BestieTokens.cBrand,
                              onPressed: _currentPosition == null
                                  ? _loadCurrentPosition
                                  : () {
                                      try {
                                        _mapController.move(_currentPosition!, 16);
                                      } catch (_) {}
                                    },
                              child: const Icon(Icons.my_location),
                            ),
                          ),
                        ],
                      ),
              ),
            ),
          ),

          const SizedBox(height: 16),

          ElevatedButton.icon(
            icon: const Icon(Icons.settings_suggest),
            label: const Text('INTELLIGENT ROUTE OPTIMIZATION'),
            style: ElevatedButton.styleFrom(
              backgroundColor: BestieTokens.cBrand,
              foregroundColor: Colors.white,
            ),
            onPressed: () {
              _showRouteOptimizationScreen(context, appProvider);
            },
          ),
          const SizedBox(height: 60),
        ],
      ),
    );
  }

  List<latlong.LatLng> _safeDirectionPoints(AppProvider provider) {
    try {
      final points = _buildDirectionPoints(provider);
      if (points.length < 2) return const [];
      final filtered = _filterLocalCluster(points, anchor: _currentPosition);
      if (!_polylineIsLocal(filtered)) return const [];
      return filtered;
    } catch (_) {
      return const [];
    }
  }

  latlong.LatLng _initialMapTarget(AppProvider provider) {
    if (_currentPosition != null) return _currentPosition!;
    final points = _buildOutletPoints(provider);
    if (points.isNotEmpty) return points.first;
    return const latlong.LatLng(17.3850, 78.4867); // Hyderabad fallback (not world-default)
  }

  bool _isValidMapCoord(double? lat, double? lng) {
    if (lat == null || lng == null) return false;
    if (lat.abs() < 0.01 && lng.abs() < 0.01) return false; // reject Null Island / (0,0)
    if (lat < -85 || lat > 85 || lng < -180 || lng > 180) return false;
    return true;
  }

  /// Keep only points that sit near the user's location or a local cluster (avoids Africa↔India lines).
  List<latlong.LatLng> _filterLocalCluster(List<latlong.LatLng> points, {latlong.LatLng? anchor}) {
    if (points.length <= 1) return points;
    final center = anchor ??
        latlong.LatLng(
          points.map((p) => p.latitude).reduce((a, b) => a + b) / points.length,
          points.map((p) => p.longitude).reduce((a, b) => a + b) / points.length,
        );
    const maxKm = 250.0;
    final local = points.where((p) {
      final km = const latlong.Distance().as(latlong.LengthUnit.Kilometer, center, p);
      return km <= maxKm;
    }).toList();
    return local.isNotEmpty ? local : [points.first];
  }

  /// Route line: current GPS → nearest-outlet order from Compute Optimal.
  List<latlong.LatLng> _buildDirectionPoints(AppProvider provider) {
    final opt = provider.optimizedRoute;
    if (opt == null) return const [];

    final points = <latlong.LatLng>[];
    if (_currentPosition != null &&
        _isValidMapCoord(_currentPosition!.latitude, _currentPosition!.longitude)) {
      points.add(_currentPosition!);
    } else {
      final startLat = double.tryParse(opt['startLatitude']?.toString() ?? '');
      final startLng = double.tryParse(opt['startLongitude']?.toString() ?? '');
      if (_isValidMapCoord(startLat, startLng)) {
        points.add(latlong.LatLng(startLat!, startLng!));
      }
    }

    final seq = opt['stopSequence'];
    if (seq is List) {
      for (final stop in seq) {
        if (stop is! Map) continue;
        final lat = double.tryParse(stop['latitude']?.toString() ?? '');
        final lng = double.tryParse(stop['longitude']?.toString() ?? '');
        if (!_isValidMapCoord(lat, lng)) continue;
        points.add(latlong.LatLng(lat!, lng!));
      }
    }
    return points;
  }

  /// Blue "you are here" only — no red outlet pins on the map.
  // Marker is drawn inside `_StableRouteMap` via `_positionListenable`.

  List<latlong.LatLng> _buildOutletPoints(AppProvider provider) {
    // Prefer optimized stop order when available — matches what Compute Optimal produced.
    final opt = provider.optimizedRoute;
    if (opt != null && opt['stopSequence'] is List) {
      final seq = (opt['stopSequence'] as List)
          .map((stop) {
            final lat = double.tryParse(stop['latitude']?.toString() ?? '');
            final lng = double.tryParse(stop['longitude']?.toString() ?? '');
            if (!_isValidMapCoord(lat, lng)) return null;
            return latlong.LatLng(lat!, lng!);
          })
          .whereType<latlong.LatLng>()
          .toList();
      return _filterLocalCluster(seq, anchor: _currentPosition);
    }

    final raw = provider.plannedOutlets
        .map((outlet) {
          final lat = double.tryParse(outlet['latitude']?.toString() ?? '');
          final lng = double.tryParse(outlet['longitude']?.toString() ?? '');
          if (!_isValidMapCoord(lat, lng)) return null;
          return latlong.LatLng(lat!, lng!);
        })
        .whereType<latlong.LatLng>()
        .toList();
    return _filterLocalCluster(raw, anchor: _currentPosition);
  }

  bool _polylineIsLocal(List<latlong.LatLng> points) {
    if (points.length < 2) return false;
    final dist = const latlong.Distance();
    for (var i = 0; i < points.length; i++) {
      for (var j = i + 1; j < points.length; j++) {
        final km = dist.as(latlong.LengthUnit.Kilometer, points[i], points[j]);
        if (km > 250) return false;
      }
    }
    return true;
  }

  void _fitMapToPoints(List<latlong.LatLng> points) {
    if (points.isEmpty) return;
    try {
      if (points.length == 1) {
        _mapController.move(points.first, 14);
        return;
      }
      final bounds = LatLngBounds.fromPoints(points);
      _mapController.fitCamera(
        CameraFit.bounds(bounds: bounds, padding: const EdgeInsets.all(48)),
      );
    } catch (_) {
      _mapController.move(points.first, 13);
    }
  }

  void _showOutletMapActions(BuildContext context, Map<String, dynamic> outlet) {
    showModalBottomSheet(
      context: context,
      builder: (context) {
        final name = outlet['name']?.toString() ?? 'Outlet';
        final address = outlet['address']?.toString() ?? 'Address not available';

        return Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              Text(address, style: const TextStyle(color: Colors.grey)),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                icon: const Icon(Icons.open_in_new),
                label: const Text('OPEN THIS ADDRESS IN MAPS'),
                onPressed: () {
                  Navigator.pop(context);
                  _openInMaps(outlet);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _openInMaps(Map<String, dynamic> outlet) async {
    final lat = double.tryParse(outlet['latitude']?.toString() ?? '');
    final lng = double.tryParse(outlet['longitude']?.toString() ?? '');
    final label = Uri.encodeComponent(outlet['name']?.toString() ?? outlet['address']?.toString() ?? 'Outlet');

    final uri = lat != null && lng != null
        ? Uri.parse('https://www.google.com/maps/search/?api=1&query=$lat,$lng($label)')
        : Uri.parse('https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent(outlet['address']?.toString() ?? '')}');

    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  void _showRouteOptimizationScreen(BuildContext context, AppProvider provider) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Generate Optimized Path'),
          content: const Text('This will use your current GPS location and today\'s planned outlet coordinates to arrange the nearest visit sequence.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('CANCEL'),
            ),
            ElevatedButton(
              onPressed: () async {
                Navigator.pop(context);

                if (provider.plannedOutlets.isEmpty) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Please select a route or add outlets before optimizing.'), backgroundColor: Colors.orange),
                    );
                  }
                  return;
                }

                Position position;
                try {
                  final resolved = await DeviceLocation.resolvePosition(timeLimit: const Duration(seconds: 8));
                  if (resolved == null) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Turn on location / allow GPS to optimize the route.'), backgroundColor: Colors.orange),
                      );
                    }
                    return;
                  }
                  position = resolved;
                } catch (_) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Unable to fetch current GPS location. Please try again.'), backgroundColor: Colors.red),
                    );
                  }
                  return;
                }

                if (!mounted) return;
                final next = latlong.LatLng(position.latitude, position.longitude);
                _currentPosition = next;
                _positionListenable.value = next;

                final success = await provider.generateOptimizedRoute(
                  provider.plannedOutlets.map((o) => o['id']?.toString() ?? '').where((id) => id.isNotEmpty).toList(),
                  [],
                  position.latitude,
                  position.longitude,
                );

                if (success && context.mounted) {
                  // Draw directions starting from the user's GPS, then fit the map.
                  final points = _buildDirectionPoints(provider);
                  setState(() {});
                  _fitMapToPoints(points.isNotEmpty ? points : _buildOutletPoints(provider));
                  _showOptimizedRouteSequenceDialog(context, provider);
                } else if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('No outlets with valid locations found for optimization.'), backgroundColor: Colors.orange),
                  );
                }
              },
              child: const Text('COMPUTE OPTIMAL'),
            ),
          ],
        );
      },
    );
  }

  void _showOptimizedRouteSequenceDialog(BuildContext context, AppProvider provider) {
    showDialog(
      context: context,
      builder: (context) {
        final opt = provider.optimizedRoute;
        if (opt == null) return const SizedBox();

        final seq = opt['stopSequence'] as List<dynamic>;

        return AlertDialog(
          title: const Text('Optimized Routing Plan'),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView(
              shrinkWrap: true,
              children: [
                Text('Total Stops: ${opt['totalStops']}'),
                Text('Straight-line Distance: ${(opt['estimatedDistanceKm'] ?? 0.0).toStringAsFixed(2)} KM'),
                const Text('Travel time will be shown by the Maps app when navigation opens.', style: TextStyle(fontSize: 12, color: Colors.grey)),
                const Divider(),
                ...seq.map((stop) {
                  final distanceKm = double.tryParse(stop['distanceFromPreviousKm']?.toString() ?? '') ?? 0.0;

                  return ListTile(
                    leading: CircleAvatar(child: Text('${stop['order']}')),
                    title: Text(stop['name']),
                    subtitle: Text('${stop['address'] ?? 'Address not available'}\nFrom previous stop: ${distanceKm.toStringAsFixed(2)} KM'),
                    isThreeLine: true,
                    trailing: IconButton(
                      icon: const Icon(Icons.navigation_outlined, color: Colors.blue),
                      tooltip: 'Launch Map Navigation',
                      onPressed: () {
                        _openOptimizedStopInMaps(stop);
                      },
                    ),
                  );
                }),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('DISMISS'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _openOptimizedStopInMaps(Map<String, dynamic> stop) async {
    final lat = double.tryParse(stop['latitude']?.toString() ?? '');
    final lng = double.tryParse(stop['longitude']?.toString() ?? '');
    final label = Uri.encodeComponent(stop['name']?.toString() ?? stop['address']?.toString() ?? 'Outlet');

    final uri = lat != null && lng != null
        ? Uri.parse('https://www.google.com/maps/search/?api=1&query=$lat,$lng($label)')
        : Uri.parse('https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent(stop['address']?.toString() ?? '')}');

    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}

// LeadsTab is in leads_tab.dart

// ---------------- INCIDENTS & REPORTS TAB ----------------
class IncidentsTab extends StatefulWidget {
  const IncidentsTab({super.key});

  @override
  State<IncidentsTab> createState() => _IncidentsTabState();
}

class _IncidentsTabState extends State<IncidentsTab> {
  final _formKey = GlobalKey<FormState>();
  final _descController = TextEditingController();
  String _selectedType = 'VEHICLE';
  final List<String> _capturedMediaPaths = [];

  @override
  void dispose() {
    _descController.dispose();
    super.dispose();
  }

  void _submitIncident() async {
    if (_formKey.currentState!.validate()) {
      final provider = Provider.of<AppProvider>(context, listen: false);

      final success = await provider.reportIncident(
        _selectedType,
        _descController.text.trim(),
        _capturedMediaPaths,
        [],
      );

      if (mounted) {
        if (success) {
          _descController.clear();
          setState(() {
            _capturedMediaPaths.clear();
          });
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Incident reported with actual captured media! Manager alert sent via FCM.'), backgroundColor: BestieTokens.cBrand),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final appProvider = Provider.of<AppProvider>(context);

    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.fromLTRB(16, 16, 16, MediaQuery.of(context).padding.bottom + 100),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Card(
            color: BestieTokens.cBrandSoft,
            child: const Padding(
              padding: EdgeInsets.all(12.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('What are Field Reports?', style: TextStyle(fontWeight: FontWeight.bold, color: BestieTokens.cBrand)),
                  SizedBox(height: 6),
                  Text(
                    'Use this to report problems during your field day — vehicle breakdown, medical issue, '
                    'outlet closed, blocked road, or anything that stops your work. Your manager is notified.',
                    style: TextStyle(fontSize: 13, color: Colors.black87),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          // Incident Log form (Module 6)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Report a Field Problem', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: BestieTokens.cBrand)),
                    const SizedBox(height: 12),
                    
                    // Category dropdown
                    DropdownButtonFormField<String>(
                      value: _selectedType,
                      decoration: const InputDecoration(labelText: 'Problem Type', border: OutlineInputBorder()),
                      onChanged: (val) {
                        if (val != null) {
                          setState(() {
                            _selectedType = val;
                          });
                        }
                      },
                      items: const [
                        DropdownMenuItem(value: 'VEHICLE', child: Text('Vehicle Breakdown')),
                        DropdownMenuItem(value: 'MEDICAL', child: Text('Medical Emergency')),
                        DropdownMenuItem(value: 'OUTLET_CLOSED', child: Text('Outlet Closed')),
                        DropdownMenuItem(value: 'BLOCKED', child: Text('Route Blocked')),
                        DropdownMenuItem(value: 'OTHER', child: Text('Other / Custom')),
                      ],
                    ),

                    const SizedBox(height: 12),

                    // Description text input (mandatory, min 20 chars)
                    TextFormField(
                      controller: _descController,
                      maxLines: 3,
                      decoration: const InputDecoration(
                        labelText: 'Detailed Description',
                        alignLabelWithHint: true,
                        helperText: 'Describe the exception clearly. Min 20 characters.',
                        border: OutlineInputBorder(),
                      ),
                      validator: (value) {
                        if (value == null || value.trim().length < 20) {
                          return 'Description must be at least 20 characters long';
                        }
                        return null;
                      },
                    ),

                    const SizedBox(height: 12),

                    // Photo attachment trigger (Module 6)
                    OutlinedButton.icon(
                      icon: const Icon(Icons.add_a_photo_outlined),
                      label: const Text('ATTACH CAPTURED MEDIA (MAX 3)'),
                      onPressed: () async {
                        final ImagePicker picker = ImagePicker();
                        XFile? photo;
                        try {
                          photo = await picker.pickImage(source: ImageSource.camera);
                        } catch (e) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Failed to access camera: $e'), backgroundColor: Colors.red),
                            );
                          }
                          return;
                        }

                        if (photo != null) {
                          setState(() {
                            if (_capturedMediaPaths.length < 3) {
                              _capturedMediaPaths.add(photo!.path);
                            } else {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Maximum 3 files are allowed.'), backgroundColor: Colors.orange),
                              );
                            }
                          });
                        }
                      },
                    ),

                    if (_capturedMediaPaths.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      SizedBox(
                        height: 80,
                        child: ListView.builder(
                          scrollDirection: Axis.horizontal,
                          itemCount: _capturedMediaPaths.length,
                          itemBuilder: (context, idx) {
                            return Padding(
                              padding: const EdgeInsets.only(right: 8.0),
                              child: Stack(
                                children: [
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(8),
                                    child: Image.file(
                                      File(_capturedMediaPaths[idx]),
                                      width: 80,
                                      height: 80,
                                      fit: BoxFit.cover,
                                    ),
                                  ),
                                  Positioned(
                                    right: 0,
                                    top: 0,
                                    child: GestureDetector(
                                      onTap: () {
                                        setState(() {
                                          _capturedMediaPaths.removeAt(idx);
                                        });
                                      },
                                      child: const CircleAvatar(
                                        radius: 12,
                                        backgroundColor: Colors.black54,
                                        child: Icon(Icons.close, size: 14, color: Colors.white),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                    ],

                    const SizedBox(height: 16),

                    ElevatedButton(
                      onPressed: _submitIncident,
                      style: ElevatedButton.styleFrom(backgroundColor: BestieTokens.cBrand, foregroundColor: Colors.white),
                      child: const Text('SUBMIT REPORT & ALERT MANAGER'),
                    ),
                  ],
                ),
              ),
            ),
          ),

          const SizedBox(height: 16),

          // Incident History list
          const Padding(
            padding: EdgeInsets.only(left: 8.0, bottom: 8),
            child: Text('MY REPORTED FIELD PROBLEMS', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey)),
          ),

          if (appProvider.userIncidents.isEmpty)
            const Center(child: Padding(padding: EdgeInsets.all(24.0), child: Text('No field reports logged yet.', style: TextStyle(color: Colors.grey))))
          else
            ...appProvider.userIncidents.map((incident) {
              final isResolved = incident['resolutionStatus'] == 'RESOLVED';
              final typeLabel = _formatIncidentType(incident['incidentType']?.toString());
              final desc = incident['description']?.toString() ?? '';
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Card(
                  color: isResolved ? BestieTokens.cBrandSoft : Colors.white,
                  child: ListTile(
                    onTap: () => _openIncidentDetail(context, incident),
                    leading: Icon(
                      isResolved ? Icons.check_circle : Icons.report_problem_outlined,
                      color: isResolved ? BestieTokens.cBrand : BestieTokens.cText,
                    ),
                    title: Text('Category: $typeLabel'),
                    subtitle: Text(
                      desc,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: Text(
                      incident['resolutionStatus']?.toString() ?? 'OPEN',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: isResolved ? BestieTokens.cBrand : BestieTokens.cText,
                      ),
                    ),
                  ),
                ),
              );
            }),
        ],
      ),
    );
  }

  String _formatIncidentType(String? raw) {
    if (raw == null || raw.trim().isEmpty) return 'Other';
    return raw
        .replaceAll('_', ' ')
        .split(' ')
        .where((w) => w.isNotEmpty)
        .map((w) => '${w[0].toUpperCase()}${w.substring(1).toLowerCase()}')
        .join(' ');
  }

  void _openIncidentDetail(BuildContext context, Map incident) {
    final isResolved = incident['resolutionStatus'] == 'RESOLVED';
    final typeLabel = _formatIncidentType(incident['incidentType']?.toString());
    final desc = incident['description']?.toString() ?? '';
    final createdAt = incident['createdAt']?.toString() ?? '';
    final images = incident['imageUrls'] is List
        ? List.from(incident['imageUrls'] as List)
        : <dynamic>[];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.fromLTRB(20, 16, 20, MediaQuery.of(ctx).padding.bottom + 20),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(typeLabel, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    ),
                    Text(
                      isResolved ? 'RESOLVED' : 'OPEN',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: isResolved ? BestieTokens.cBrand : BestieTokens.cText,
                      ),
                    ),
                  ],
                ),
                if (createdAt.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text('Reported: $createdAt', style: const TextStyle(fontSize: 12, color: Colors.black54)),
                ],
                const SizedBox(height: 12),
                Text(desc.isEmpty ? 'No description provided.' : desc, style: const TextStyle(fontSize: 15, height: 1.4)),
                if (images.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  const Text('Attached media', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 100,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: images.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 8),
                      itemBuilder: (_, idx) {
                        final path = images[idx]?.toString() ?? '';
                        if (path.isEmpty) return const SizedBox.shrink();
                        return ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: path.startsWith('http') || path.startsWith('data:')
                              ? Image.network(path, width: 100, height: 100, fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) => Container(
                                    width: 100,
                                    height: 100,
                                    color: Colors.grey.shade200,
                                    child: const Icon(Icons.broken_image),
                                  ))
                              : Image.file(File(path), width: 100, height: 100, fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) => Container(
                                    width: 100,
                                    height: 100,
                                    color: Colors.grey.shade200,
                                    child: const Icon(Icons.broken_image),
                                  )),
                        );
                      },
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                OutlinedButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('CLOSE'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// -------------------------------------------------------------
// ---------------- ADMIN & MANAGER MOBILE DASHBOARD -----------
// -------------------------------------------------------------

class _AdminPanelCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? backgroundColor;
  final VoidCallback? onTap;

  const _AdminPanelCard({
    required this.child,
    this.padding = const EdgeInsets.all(BestieTokens.s3),
    this.backgroundColor,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(BestieTokens.rLg);
    final content = Padding(padding: padding, child: child);

    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      color: backgroundColor ?? BestieTokens.cSurface,
      shape: RoundedRectangleBorder(
        borderRadius: radius,
        side: const BorderSide(color: BestieTokens.cBorderSoft),
      ),
      child: onTap == null
          ? content
          : InkWell(
              onTap: onTap,
              borderRadius: radius,
              child: content,
            ),
    );
  }
}

Widget _adminStatusChip(
  String label, {
  required Color backgroundColor,
  required Color foregroundColor,
  IconData? icon,
}) {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      color: backgroundColor,
      borderRadius: BorderRadius.circular(BestieTokens.rPill),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[
          Icon(icon, size: 12, color: foregroundColor),
          const SizedBox(width: 4),
        ],
        Text(
          label,
          style: TextStyle(
            fontSize: 10,
            color: foregroundColor,
            fontWeight: BestieTokens.fwBold,
            letterSpacing: 0.2,
          ),
        ),
      ],
    ),
  );
}

class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  int _currentIndex = 0;

  @override
  Widget build(BuildContext context) {
    final appProvider = Provider.of<AppProvider>(context);
    final isSuperAdmin = (appProvider.role ?? '').toLowerCase() == 'super_admin';

    // Super admin: hide Team + Incidents (keep widgets in codebase for other roles).
    final tabs = <Widget>[
      const AdminHomeTab(),
      if (!isSuperAdmin) const AdminTeamTab(),
      const AdminLiveActivitiesTab(),
      if (!isSuperAdmin) const AdminIncidentOversightTab(),
    ];

    final navItems = <BestieNavItem>[
      const BestieNavItem(Icons.insights_outlined, Icons.insights, 'Oversight'),
      if (!isSuperAdmin) const BestieNavItem(Icons.people_outline, Icons.people, 'Team'),
      const BestieNavItem(Icons.assignment_outlined, Icons.assignment, 'Logs'),
      if (!isSuperAdmin)
        const BestieNavItem(Icons.notification_important_outlined, Icons.notification_important, 'Incidents'),
    ];

    // Clamp index if role/session changes mid-session.
    final safeIndex = _currentIndex.clamp(0, tabs.length - 1);

    String appBarTitleFor(int index) {
      if (isSuperAdmin) {
        return index == 1 ? 'Field Activity Audit' : 'Incident Oversight';
      }
      return index == 1
          ? 'Field Force Directory'
          : index == 2
              ? 'Field Activity Audit'
              : 'Incident Oversight';
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final nav = Navigator.of(context);
        if (nav.canPop()) {
          nav.pop();
          return;
        }
        if (safeIndex != 0) {
          setState(() => _currentIndex = 0);
          return;
        }
        final leave = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Exit app?'),
            content: const Text('Do you want to close Marketing Executives?'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Stay')),
              ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Exit')),
            ],
          ),
        );
        if (leave == true && context.mounted) {
          SystemNavigator.pop();
        }
      },
      child: Scaffold(
      backgroundColor: BestieTokens.cBg,
      extendBody: true,
      appBar: safeIndex == 0
          ? BestieShellAppBar(
              actions: [
                IconButton(
                  icon: const Icon(Icons.refresh),
                  tooltip: 'Refresh Analytics',
                  onPressed: () async {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Refreshing management metrics...')),
                    );
                    await appProvider.fetchAdminDashboardData();
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.logout),
                  tooltip: 'Logout',
                  onPressed: () async {
                    final deviceId = await DeviceId.get();
                    await appProvider.logout(deviceId);
                  },
                ),
              ],
            )
          : AppBar(
              title: Text(appBarTitleFor(safeIndex)),
              actions: [
                IconButton(
                  icon: const Icon(Icons.refresh),
                  tooltip: 'Refresh Analytics',
                  onPressed: () async {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Refreshing management metrics...')),
                    );
                    await appProvider.fetchAdminDashboardData();
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.logout),
                  tooltip: 'Logout',
                  onPressed: () async {
                    final deviceId = await DeviceId.get();
                    await appProvider.logout(deviceId);
                  },
                ),
              ],
            ),
      body: tabs[safeIndex],
      bottomNavigationBar: BestieBottomNav(
        currentIndex: safeIndex,
        onTap: (index) {
          setState(() {
            _currentIndex = index;
          });
        },
        items: navItems,
      ),
    ),
    );
  }
}

// Shared create-executive form for Admin Home + Team tabs.
Future<void> showCreateExecutiveSheet(BuildContext context, AppProvider provider) async {
  final formKey = GlobalKey<FormState>();
  final nameController = TextEditingController();
  final emailController = TextEditingController();
  final passController = TextEditingController();
  final myRole = (provider.role ?? '').toLowerCase();
  final isOrgAdmin = myRole == 'admin' || myRole == 'super_admin';
  final roleOptions = isOrgAdmin
      ? const [
          ('executive', 'Executive'),
          ('manager', 'Manager'),
          ('admin', 'Admin'),
        ]
      : const [
          ('executive', 'Executive'),
        ];
  var selectedRole = 'executive';
  var obscurePassword = true;

  InputDecoration fieldDecoration({
    required String label,
    required IconData icon,
    String? hint,
    Widget? suffix,
  }) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      floatingLabelBehavior: FloatingLabelBehavior.auto,
      labelStyle: const TextStyle(color: BestieTokens.cBrand, fontWeight: FontWeight.w600),
      floatingLabelStyle: const TextStyle(color: BestieTokens.cBrand, fontWeight: FontWeight.w600),
      prefixIcon: Icon(icon, color: BestieTokens.cTextMuted),
      suffixIcon: suffix,
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: BestieTokens.cBorder),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: BestieTokens.cBorder),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: BestieTokens.cBrand, width: 1.6),
      ),
    );
  }

  await showDialog(
    context: context,
    barrierDismissible: false,
    builder: (sheetContext) {
      final media = MediaQuery.of(sheetContext);
      return StatefulBuilder(
        builder: (sheetContext, setSheetState) {
          return Dialog(
            insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: media.size.height * 0.9,
                maxWidth: 420,
              ),
              child: Padding(
                padding: EdgeInsets.fromLTRB(20, 20, 20, 16 + media.viewInsets.bottom * 0.15),
                child: Form(
                  key: formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 44,
                            height: 44,
                            decoration: const BoxDecoration(
                              color: BestieTokens.cBrandSoft,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.person_add_alt_1, color: BestieTokens.cBrand),
                          ),
                          const SizedBox(width: 12),
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Create Team Member',
                                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: BestieTokens.cText),
                                ),
                                SizedBox(height: 4),
                                Text(
                                  'Add a new team member and assign a role. They will be able to log in with the provided email and password.',
                                  style: TextStyle(fontSize: 12, color: BestieTokens.cTextMuted, height: 1.35),
                                ),
                              ],
                            ),
                          ),
                          InkWell(
                            onTap: () => Navigator.pop(sheetContext),
                            borderRadius: BorderRadius.circular(20),
                            child: Container(
                              width: 34,
                              height: 34,
                              decoration: const BoxDecoration(
                                color: BestieTokens.cSurface2,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.close, size: 18, color: BestieTokens.cTextSoft),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      Flexible(
                        child: SingleChildScrollView(
                          child: Column(
                            children: [
                              TextFormField(
                                controller: nameController,
                                decoration: fieldDecoration(
                                  label: 'Full Name',
                                  icon: Icons.person_outline,
                                  hint: 'Enter full name',
                                ),
                                validator: (v) => v == null || v.trim().isEmpty ? 'Please enter a name' : null,
                              ),
                              const SizedBox(height: 14),
                              TextFormField(
                                controller: emailController,
                                keyboardType: TextInputType.emailAddress,
                                decoration: fieldDecoration(
                                  label: 'Email Address',
                                  icon: Icons.mail_outline,
                                  hint: 'Enter email address',
                                ),
                                validator: (v) {
                                  if (v == null || v.trim().isEmpty) return 'Please enter an email';
                                  if (!AppProvider.isValidLoginEmail(v)) {
                                    return 'Invalid email (check typos like .com.com)';
                                  }
                                  return null;
                                },
                              ),
                              const SizedBox(height: 14),
                              TextFormField(
                                controller: passController,
                                obscureText: obscurePassword,
                                decoration: fieldDecoration(
                                  label: 'Initial Password',
                                  icon: Icons.lock_outline,
                                  hint: 'Enter initial password',
                                  suffix: IconButton(
                                    onPressed: () => setSheetState(() => obscurePassword = !obscurePassword),
                                    icon: Icon(
                                      obscurePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                                      color: BestieTokens.cTextMuted,
                                    ),
                                  ),
                                ),
                                validator: (v) => v == null || v.length < 6 ? 'Password must be at least 6 characters' : null,
                              ),
                              const SizedBox(height: 14),
                              DropdownButtonFormField<String>(
                                value: selectedRole,
                                decoration: fieldDecoration(
                                  label: 'Role',
                                  icon: Icons.verified_user_outlined,
                                  hint: 'Select role',
                                ),
                                items: roleOptions
                                    .map(
                                      (opt) => DropdownMenuItem<String>(
                                        value: opt.$1,
                                        child: Text(opt.$2),
                                      ),
                                    )
                                    .toList(),
                                onChanged: (value) {
                                  if (value == null) return;
                                  setSheetState(() => selectedRole = value);
                                },
                              ),
                              if (!isOrgAdmin) ...[
                                const SizedBox(height: 8),
                                const Text(
                                  'Your role can create Executive accounts only.',
                                  style: TextStyle(fontSize: 11, color: BestieTokens.cTextMuted),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 18),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: () async {
                            if (!(formKey.currentState?.validate() ?? false)) return;
                            Navigator.pop(sheetContext);
                            final success = await provider.createExecutive(
                              nameController.text.trim(),
                              emailController.text.trim(),
                              passController.text,
                              role: selectedRole,
                            );
                            if (!context.mounted) return;
                            final roleLabel = selectedRole[0].toUpperCase() + selectedRole.substring(1);
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  success
                                      ? '$roleLabel account created. They can log in with this email and password.'
                                      : (provider.lastActionError ??
                                          'Could not create account. Email may already exist, or your role lacks permission.'),
                                ),
                                backgroundColor: success ? BestieTokens.cBrand : BestieTokens.cText,
                              ),
                            );
                          },
                          icon: const Icon(Icons.person_add_alt_1, size: 18),
                          label: const Text('Create Account'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: BestieTokens.cBrand,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      );
    },
  );

  nameController.dispose();
  emailController.dispose();
  passController.dispose();
}

class AdminHomeTab extends StatelessWidget {
  const AdminHomeTab({super.key});

  static const _actionCardHeight = 78.0;
  static const _sectionGap = 18.0;
  static const _cardGap = 10.0;

  @override
  Widget build(BuildContext context) {
    final appProvider = Provider.of<AppProvider>(context);
    final stats = appProvider.adminStats ?? {};
    final isSuperAdmin = (appProvider.role ?? '').toLowerCase() == 'super_admin';
    final orgName = stats['org']?['name']?.toString() ?? 'Loading Corp...';
    final email = appProvider.email ?? stats['org']?['email']?.toString() ?? 'Signed in';
    final hasOpenIncidents = (stats['open_incidents_count'] ?? 0) > 0;

    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(16, 14, 16, MediaQuery.of(context).padding.bottom + 100),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Compact horizontal workspace banner (matches reference layout)
          Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(BestieTokens.rLg),
              onTap: () => _showManagementDeskInfo(context, appProvider, orgName),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(BestieTokens.rLg),
                child: Container(
                  decoration: const BoxDecoration(gradient: BestieTokens.gBrand),
                  padding: const EdgeInsets.fromLTRB(14, 14, 12, 14),
                  child: Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.22),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.apartment_rounded, color: Colors.white, size: 24),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              orgName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 17,
                                fontWeight: BestieTokens.fwBold,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              email,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 11),
                            ),
                            Text(
                              'Workspace: $orgName',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(color: Colors.white.withValues(alpha: 0.72), fontSize: 11),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(BestieTokens.rPill),
                          border: Border.all(color: Colors.white.withValues(alpha: 0.55)),
                          color: Colors.white.withValues(alpha: 0.12),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'MANAGEMENT DESK',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 9,
                                fontWeight: BestieTokens.fwBold,
                                letterSpacing: 0.2,
                              ),
                            ),
                            SizedBox(width: 4),
                            Icon(Icons.arrow_forward_ios_rounded, color: Colors.white, size: 10),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

          if (appProvider.subscriptionBannerText != null) ...[
            const SizedBox(height: 12),
            Card(
              color: BestieTokens.cBrandSoft,
              child: ListTile(
                leading: Icon(
                  appProvider.isPastGracePeriod
                      ? Icons.lock
                      : appProvider.isInGracePeriod
                          ? Icons.schedule
                          : Icons.card_giftcard,
                  color: BestieTokens.cBrand,
                ),
                title: Text(
                  appProvider.isPastGracePeriod
                      ? 'Payment required'
                      : appProvider.isInGracePeriod
                          ? 'Grace period'
                          : 'Subscription',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                subtitle: Text(appProvider.subscriptionBannerText!),
              ),
            ),
          ],

          const SizedBox(height: _sectionGap),
          Row(
            children: [
              const Expanded(
                child: Text(
                  'LIVE FIELD KPIS',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: BestieTokens.fwBold,
                    letterSpacing: 0.6,
                    color: BestieTokens.cTextMuted,
                  ),
                ),
              ),
              Container(
                width: 7,
                height: 7,
                decoration: const BoxDecoration(
                  color: BestieTokens.cBrand,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
              const Text(
                'Updated just now',
                style: TextStyle(fontSize: 11, color: BestieTokens.cTextMuted),
              ),
            ],
          ),
          const SizedBox(height: 10),

              // One-row KPI strip (equal width, fixed height like reference)
          SizedBox(
            height: 118,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: _buildKpiCard(
                    'Active Execs',
                    '${stats['active_executives'] ?? 0}',
                    Icons.directions_walk_rounded,
                    BestieTokens.cBrand,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildKpiCard(
                    'Total Distance',
                    '${(stats['distance_covered_km'] ?? 0.0).toStringAsFixed(1)} KM',
                    Icons.map_outlined,
                    const Color(0xFF1F3A8A),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildKpiCard(
                    'Visits Done',
                    '${stats['visits_completed'] ?? 0}',
                    Icons.storefront_outlined,
                    BestieTokens.cBrandStrong,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildKpiCard(
                    'Sales Value',
                    '₹${(stats['sales_value_total'] ?? 0.0).toStringAsFixed(2)}',
                    Icons.payments_outlined,
                    BestieTokens.cText,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 12),

          // Compact status banner — same visual weight as action cards
          SizedBox(
            height: _actionCardHeight,
            child: _AdminPanelCard(
              backgroundColor: hasOpenIncidents ? const Color(0xFFF3F4F6) : const Color(0xFFEDF4FF),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Stack(
                children: [
                  Positioned(
                    right: 0,
                    top: 0,
                    bottom: 0,
                    child: Icon(
                      Icons.verified_user_outlined,
                      size: 42,
                      color: BestieTokens.cBrand.withValues(alpha: 0.10),
                    ),
                  ),
                  Row(
                    children: [
                      Icon(
                        hasOpenIncidents ? Icons.notifications_active_outlined : Icons.check_circle,
                        color: BestieTokens.cBrand,
                        size: 28,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              hasOpenIncidents ? 'Incident Attention Needed' : 'All Systems Nominal',
                              style: const TextStyle(
                                fontWeight: BestieTokens.fwBold,
                                fontSize: 15,
                                color: BestieTokens.cText,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              hasOpenIncidents
                                  ? 'Open the Incidents tab to resolve the latest field issue.'
                                  : 'Field sales force is moving smoothly. No emergency exceptions reported.',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 12,
                                color: BestieTokens.cTextSoft,
                                height: 1.3,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: _sectionGap),
          const Text(
            'QUICK ACTIONS',
            style: TextStyle(
              fontSize: 11,
              fontWeight: BestieTokens.fwBold,
              letterSpacing: 0.6,
              color: BestieTokens.cTextMuted,
            ),
          ),
          const SizedBox(height: 10),

          if (isSuperAdmin) ...[
            _buildAdminShortcutCard(
              title: 'Platform Super Admin',
              subtitle: 'Org approval tools only. Team & Logs need an organisation admin.',
              icon: Icons.info_outline,
              trailing: const Icon(Icons.chevron_right, color: BestieTokens.cTextMuted),
            ),
            const SizedBox(height: _cardGap),
            _buildAdminShortcutCard(
              title: 'Organisations',
              subtitle: appProvider.pendingOrganisations.isEmpty
                  ? 'View all orgs. Approve or reject pending requests.'
                  : '${appProvider.pendingOrganisations.length} pending approval.',
              icon: Icons.business,
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (appProvider.pendingOrganisations.isNotEmpty)
                    Container(
                      margin: const EdgeInsets.only(right: 6),
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: BestieTokens.cBrand,
                        borderRadius: BorderRadius.circular(BestieTokens.rPill),
                      ),
                      child: Text(
                        '${appProvider.pendingOrganisations.length}',
                        style: const TextStyle(color: Colors.white, fontWeight: BestieTokens.fwBold, fontSize: 11),
                      ),
                    ),
                  const Icon(Icons.chevron_right, color: BestieTokens.cTextMuted),
                ],
              ),
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const OrganisationsAdminScreen()),
                );
              },
            ),
            const SizedBox(height: _cardGap),
          ],

          if (!isSuperAdmin) ...[
            _buildAdminShortcutCard(
              title: 'Create Team Member',
              subtitle: 'Add Admin, Manager, or Executive (name, email, password, role).',
              icon: Icons.person_add_alt_1_rounded,
              trailing: const Icon(Icons.chevron_right, color: BestieTokens.cTextMuted),
              onTap: () => showCreateExecutiveSheet(context, appProvider),
            ),
            const SizedBox(height: _cardGap),
            _buildAdminShortcutCard(
              title: 'Products Catalog',
              subtitle: 'Manage products, brands, and categories for field orders.',
              icon: Icons.inventory_2_outlined,
              trailing: const Icon(Icons.chevron_right, color: BestieTokens.cTextMuted),
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const ProductsAdminScreen()),
                );
              },
            ),
            const SizedBox(height: _cardGap),
            _buildAdminShortcutCard(
              title: 'Automatic Visit Policy',
              subtitle: 'Min stay: ${appProvider.minimumVisitDurationMinutes} min · Selfie: ${appProvider.selfieRequired ? "Yes" : "No"}',
              icon: Icons.timer_outlined,
              trailing: const Icon(Icons.edit_outlined, color: BestieTokens.cTextMuted, size: 20),
              onTap: () => _showVisitDurationSettings(context, appProvider),
            ),
            const SizedBox(height: _cardGap),
            _buildAdminShortcutCard(
              title: 'Selfie Check-in',
              subtitle: appProvider.selfieRequired
                  ? 'Enabled. Executives must blink-capture a selfie to check in.'
                  : 'Disabled. Dwell time can auto-complete visits without selfie.',
              icon: Icons.camera_alt_outlined,
              trailing: Switch(
                value: appProvider.selfieRequired,
                activeThumbColor: Colors.white,
                activeTrackColor: BestieTokens.cBrand,
                onChanged: (value) async {
                  await appProvider.setSelfieRequired(value);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(value ? 'Selfie check-in enabled' : 'Selfie check-in disabled (default)'),
                        backgroundColor: BestieTokens.cBrand,
                      ),
                    );
                  }
                },
              ),
            ),
            const SizedBox(height: _cardGap),
          ],

          _buildAdminShortcutCard(
            title: 'Excel Report',
            subtitle: 'Save the report.',
            icon: Icons.table_chart_outlined,
            trailing: const Icon(Icons.download_outlined, color: BestieTokens.cTextMuted, size: 20),
            onTap: () async {
              final path = await appProvider.exportVisitsCsv();
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      path.isEmpty
                          ? (appProvider.lastActionError ?? 'Export failed.')
                          : 'Report saved successfully. Open it from Downloads or Files.',
                    ),
                    backgroundColor: path.isEmpty ? BestieTokens.cText : BestieTokens.cBrand,
                    duration: const Duration(seconds: 5),
                  ),
                );
              }
            },
          ),
        ],
      ),
    );
  }

  void _showManagementDeskInfo(BuildContext context, AppProvider provider, String orgName) {
    final email = provider.email ?? '—';
    final password = (provider.loginPassword ?? '').trim();
    final role = (provider.role ?? 'admin').toString();
    var showPassword = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            return Padding(
              padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.of(ctx).padding.bottom + 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Management Desk',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 18, fontWeight: BestieTokens.fwBold, color: BestieTokens.cBrand),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    orgName,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 13, color: BestieTokens.cTextMuted),
                  ),
                  const SizedBox(height: 18),
                  _infoRow('Role', role),
                  const SizedBox(height: 10),
                  _infoRow('Email', email),
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      color: BestieTokens.cSurface2,
                      borderRadius: BorderRadius.circular(BestieTokens.rMd),
                      border: Border.all(color: BestieTokens.cBorderSoft),
                    ),
                    child: Row(
                      children: [
                        const Expanded(
                          child: Text('Password', style: TextStyle(fontSize: 12, color: BestieTokens.cTextMuted)),
                        ),
                        Expanded(
                          flex: 2,
                          child: Text(
                            password.isEmpty
                                ? 'Sign in again to view password'
                                : (showPassword ? password : '••••••••'),
                            textAlign: TextAlign.right,
                            style: const TextStyle(fontWeight: BestieTokens.fwBold, fontSize: 14),
                          ),
                        ),
                        if (password.isNotEmpty)
                          IconButton(
                            visualDensity: VisualDensity.compact,
                            onPressed: () => setLocal(() => showPassword = !showPassword),
                            icon: Icon(
                              showPassword ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                              size: 20,
                              color: BestieTokens.cBrand,
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('CLOSE'),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _infoRow(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: BestieTokens.cSurface2,
        borderRadius: BorderRadius.circular(BestieTokens.rMd),
        border: Border.all(color: BestieTokens.cBorderSoft),
      ),
      child: Row(
        children: [
          Text(label, style: const TextStyle(fontSize: 12, color: BestieTokens.cTextMuted)),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: const TextStyle(fontWeight: BestieTokens.fwBold, fontSize: 14),
            ),
          ),
        ],
      ),
    );
  }

  void _showVisitDurationSettings(BuildContext context, AppProvider provider) {
    final minutesCtrl = TextEditingController(
      text: provider.minimumVisitDurationMinutes.toString(),
    );
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Minimum Visit Duration'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'How long (in minutes) an executive must stay near an outlet before auto-visit. Type any value from 1 to 480.',
              ),
              const SizedBox(height: 16),
              TextField(
                controller: minutesCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Minutes',
                  hintText: 'e.g. 3',
                  border: OutlineInputBorder(),
                  suffixText: 'min',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('CANCEL'),
            ),
            ElevatedButton(
              onPressed: () async {
                final parsed = int.tryParse(minutesCtrl.text.trim());
                if (parsed == null || parsed < 1) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Enter a valid number of minutes (1 or more).'), backgroundColor: Colors.red),
                  );
                  return;
                }
                await provider.setMinimumVisitDurationMinutes(parsed);
                if (context.mounted) Navigator.pop(context);
              },
              child: const Text('SAVE'),
            ),
          ],
        );
      },
    );
  }

  Widget _buildKpiCard(String label, String value, IconData icon, Color accent) {
    return _AdminPanelCard(
      padding: const EdgeInsets.fromLTRB(8, 10, 8, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: accent, size: 16),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 10,
              color: BestieTokens.cTextMuted,
              fontWeight: BestieTokens.fwSemibold,
            ),
          ),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: BestieTokens.fwBold,
                color: BestieTokens.cText,
              ),
            ),
          ),
          const Spacer(),
          SizedBox(
            height: 18,
            width: double.infinity,
            child: CustomPaint(painter: _KpiSparklinePainter(accent)),
          ),
        ],
      ),
    );
  }

  Widget _buildAdminShortcutCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required Widget trailing,
    VoidCallback? onTap,
  }) {
    return SizedBox(
      height: _actionCardHeight,
      child: _AdminPanelCard(
        onTap: onTap,
        padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: BestieTokens.cBrand,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Icon(icon, color: Colors.white, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: BestieTokens.fwBold, fontSize: 14),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12, color: BestieTokens.cTextSoft, height: 1.25),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 6),
            trailing,
          ],
        ),
      ),
    );
  }
}

class _KpiSparklinePainter extends CustomPainter {
  final Color color;
  const _KpiSparklinePainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color.withValues(alpha: 0.85)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final path = Path();
    final points = <Offset>[
      Offset(0, size.height * 0.65),
      Offset(size.width * 0.18, size.height * 0.45),
      Offset(size.width * 0.36, size.height * 0.72),
      Offset(size.width * 0.55, size.height * 0.35),
      Offset(size.width * 0.72, size.height * 0.55),
      Offset(size.width * 0.88, size.height * 0.28),
      Offset(size.width, size.height * 0.42),
    ];
    path.moveTo(points.first.dx, points.first.dy);
    for (var i = 1; i < points.length; i++) {
      path.lineTo(points[i].dx, points[i].dy);
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _KpiSparklinePainter oldDelegate) => oldDelegate.color != color;
}

class AdminTeamTab extends StatefulWidget {
  const AdminTeamTab({super.key});

  @override
  State<AdminTeamTab> createState() => _AdminTeamTabState();
}

class _AdminTeamTabState extends State<AdminTeamTab> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<AppProvider>(context, listen: false).fetchAdminUsersList();
    });
  }

  Future<void> _editUser(AppProvider appProvider, Map user) async {
    final nameCtrl = TextEditingController(text: user['name']?.toString() ?? '');
    final emailCtrl = TextEditingController(text: user['email']?.toString() ?? '');
    final phoneCtrl = TextEditingController(text: user['phone']?.toString() ?? '');
    final passwordCtrl = TextEditingController();
    var status = (user['accountStatus'] ?? user['status'] ?? 'active').toString().toLowerCase();
    if (status != 'active' && status != 'inactive') status = 'active';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('Edit team member'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Name')),
                TextField(controller: emailCtrl, decoration: const InputDecoration(labelText: 'Email')),
                TextField(controller: phoneCtrl, decoration: const InputDecoration(labelText: 'Phone')),
                TextField(
                  controller: passwordCtrl,
                  decoration: const InputDecoration(labelText: 'New password (optional)'),
                  obscureText: true,
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  value: status,
                  decoration: const InputDecoration(labelText: 'Account status'),
                  items: const [
                    DropdownMenuItem(value: 'active', child: Text('Active')),
                    DropdownMenuItem(value: 'inactive', child: Text('Inactive')),
                  ],
                  onChanged: (v) => setLocal(() => status = v ?? status),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save')),
          ],
        ),
      ),
    );

    if (confirmed != true) return;
    final ok = await appProvider.updateExecutive(
      userId: user['id'].toString(),
      name: nameCtrl.text.trim(),
      email: emailCtrl.text.trim(),
      phone: phoneCtrl.text.trim(),
      password: passwordCtrl.text.trim().isEmpty ? null : passwordCtrl.text.trim(),
      status: status,
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(ok ? 'User updated.' : (appProvider.lastActionError ?? 'Update failed.')),
        backgroundColor: ok ? Colors.green : Colors.red,
      ),
    );
  }

  Future<void> _deleteUser(AppProvider appProvider, Map user) async {
    final name = user['name'] ?? user['email'] ?? 'this user';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete team member?'),
        content: Text('Remove $name from the organisation? This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final ok = await appProvider.deleteExecutive(user['id'].toString());
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(ok ? 'User deleted.' : (appProvider.lastActionError ?? 'Delete failed.')),
        backgroundColor: ok ? Colors.green : Colors.red,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final appProvider = Provider.of<AppProvider>(context);
    final users = appProvider.adminUsersList;

    if (users.isEmpty) {
      final isSuper = (appProvider.role ?? '').toLowerCase() == 'super_admin';
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.groups_outlined, size: 48, color: Colors.grey),
              const SizedBox(height: 12),
              Text(
                isSuper
                    ? 'Team directory blocked for super admin on server'
                    : 'No team members loaded yet.',
                textAlign: TextAlign.center,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              Text(
                isSuper
                    ? 'Production API returns 403 for super_admin on GET /users (requires admin). Use an organisation admin account for Team/Logs, or ask backend to allow super_admin on admin routes.'
                    : 'Pull refresh from the app bar, or tap retry. Executives appear here after they are created for your organisation.',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.black54, height: 1.4),
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: () => appProvider.fetchAdminUsersList(),
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: () => appProvider.fetchAdminUsersList(),
        child: ListView.separated(
          padding: EdgeInsets.fromLTRB(16, 16, 16, MediaQuery.of(context).padding.bottom + 100),
          itemCount: users.length,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (context, idx) {
            final user = users[idx];
            final isOnline = user['isOnline'] == true;
            final accountActive = (user['accountStatus'] ?? user['status'] ?? 'active').toString().toLowerCase() == 'active';
            final checkInLabel = _formatTeamAttendanceTime(
              _firstAvailableValue(user, ['check_in_at', 'checkInAt', 'login_time', 'logged_in_at', 'last_login']),
            );
            final checkOutLabel = _formatTeamAttendanceTime(
              _firstAvailableValue(user, ['check_out_at', 'checkOutAt', 'logout_time', 'logged_out_at', 'last_logout']),
            );
            final name = (user['name'] ?? user['email'] ?? 'User').toString();
            final initial = name.isNotEmpty ? name.substring(0, 1).toUpperCase() : '?';
            final canEdit = user['canEdit'] == true;
            final canDelete = user['canDelete'] == true;

            return _AdminPanelCard(
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
              child: Padding(
                padding: EdgeInsets.zero,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        CircleAvatar(
                          backgroundColor: BestieTokens.cBrand,
                          foregroundColor: Colors.white,
                          child: Text(initial),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                              Text('${user['designation'] ?? user['role'] ?? "Field Agent"}'),
                              Text(user['email']?.toString() ?? '', style: const TextStyle(fontSize: 12, color: Colors.black54)),
                              if ((user['phone'] ?? '').toString().isNotEmpty)
                                Text(user['phone'].toString(), style: const TextStyle(fontSize: 12, color: Colors.black54)),
                            ],
                          ),
                        ),
                        Column(
                          children: [
                            _adminStatusChip(
                              isOnline ? 'ONLINE' : 'OFFLINE',
                              backgroundColor: isOnline ? BestieTokens.cBrandSoft : BestieTokens.cSurface2,
                              foregroundColor: isOnline ? BestieTokens.cBrand : BestieTokens.cTextMuted,
                            ),
                            if (!accountActive) ...[
                              const SizedBox(height: 6),
                              _adminStatusChip(
                                'INACTIVE',
                                backgroundColor: const Color(0xFFF3F4F6),
                                foregroundColor: BestieTokens.cText,
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _buildTeamAttendanceChip(
                          'Check-in',
                          checkInLabel ?? (isOnline ? 'In field now' : 'Not checked in'),
                          isOnline ? BestieTokens.cBrand : BestieTokens.cTextMuted,
                        ),
                        _buildTeamAttendanceChip(
                          'Check-out',
                          checkOutLabel ?? (isOnline ? 'Still in visit' : '—'),
                          BestieTokens.cBrand,
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    if (canEdit || canDelete || appProvider.isPlatformSuperAdmin)
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          if (appProvider.isPlatformSuperAdmin &&
                              (user['id']?.toString().isNotEmpty ?? false) &&
                              (user['role']?.toString().toLowerCase() == 'executive' ||
                                  user['role']?.toString().toLowerCase() == 'sales_executive'))
                            TextButton.icon(
                              onPressed: () async {
                                final id = user['id'].toString();
                                final ok = await appProvider.forceLogoutUser(id);
                                if (!context.mounted) return;
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      ok
                                          ? 'Device unlocked. ${user['name'] ?? 'User'} can sign in again.'
                                          : (appProvider.lastActionError ??
                                              'Could not unlock device (super_admin required on server).'),
                                    ),
                                  ),
                                );
                              },
                              icon: const Icon(Icons.lock_open, size: 18),
                              label: const Text('Unlock device'),
                            ),
                          if (canEdit)
                            TextButton.icon(
                              onPressed: () => _editUser(appProvider, user),
                              icon: const Icon(Icons.edit_outlined, size: 18),
                              label: const Text('Edit'),
                            ),
                          if (canDelete)
                            TextButton.icon(
                              onPressed: () => _deleteUser(appProvider, user),
                              icon: const Icon(Icons.delete_outline, size: 18, color: BestieTokens.cDanger),
                              label: const Text('Delete', style: TextStyle(color: BestieTokens.cDanger)),
                            ),
                          ],
                        ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => showCreateExecutiveSheet(context, appProvider),
        backgroundColor: BestieTokens.cBrand,
        foregroundColor: Colors.white,
        tooltip: 'Add Team Member',
        child: const Icon(Icons.person_add),
      ),
    );
  }

  Widget _buildTeamAttendanceChip(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(BestieTokens.rMd),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Text(
        '$label: $value',
        style: TextStyle(fontSize: 11, color: color, fontWeight: BestieTokens.fwSemibold),
      ),
    );
  }

  dynamic _firstAvailableValue(Map<dynamic, dynamic> user, List<String> keys) {
    for (final key in keys) {
      final value = user[key];
      if (value != null && value.toString().trim().isNotEmpty) return value;
    }
    return null;
  }

  String? _formatTeamAttendanceTime(dynamic value) {
    if (value == null) return null;
    final raw = value.toString();
    try {
      return DateFormat('hh:mm a').format(DateTime.parse(raw).toLocal());
    } catch (_) {
      return raw;
    }
  }
}

class AdminIncidentOversightTab extends StatelessWidget {
  const AdminIncidentOversightTab({super.key});

  @override
  Widget build(BuildContext context) {
    final appProvider = Provider.of<AppProvider>(context);

    // Filter incidents from the team to oversee
    final incidents = appProvider.userIncidents;

    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.fromLTRB(16, 16, 16, MediaQuery.of(context).padding.bottom + 100),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(
            padding: EdgeInsets.only(left: 8.0, bottom: 8),
            child: Text('EMERGENCY BREAKDOWNS & ISSUES LOG', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey)),
          ),
          
          if (incidents.isEmpty)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(40.0),
                child: Column(
                  children: [
                    Icon(Icons.check_circle_outline, size: 64, color: Colors.green),
                    SizedBox(height: 12),
                    Text('No emergency reports submitted by field agents.', style: TextStyle(color: Colors.grey)),
                  ],
                ),
              ),
            )
          else
            ...incidents.expand((inc) {
              final isResolved = inc['resolutionStatus'] == 'RESOLVED';
              return [
                _AdminPanelCard(
                backgroundColor: isResolved ? const Color(0xFFF7FAFF) : const Color(0xFFFDFEFF),
                child: Padding(
                  padding: const EdgeInsets.all(14.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              'Category: ${inc['incidentType']}',
                              style: const TextStyle(fontWeight: BestieTokens.fwBold, fontSize: 16),
                            ),
                          ),
                          const SizedBox(width: 12),
                          _adminStatusChip(
                            inc['resolutionStatus'],
                            backgroundColor: isResolved ? BestieTokens.cBrandSoft : const Color(0xFFF3F4F6),
                            foregroundColor: isResolved ? BestieTokens.cBrand : BestieTokens.cText,
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        inc['description'],
                        style: const TextStyle(fontSize: 13, color: BestieTokens.cTextSoft, height: 1.4),
                      ),
                      if ((inc['userId'] ?? '').toString().isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text('Reporter user id: ${inc['userId']}', style: const TextStyle(fontSize: 11, color: Colors.black54)),
                        ),
                      if ((inc['createdAt'] ?? '').toString().isNotEmpty)
                        Text('Reported: ${inc['createdAt']}', style: const TextStyle(fontSize: 11, color: Colors.black54)),
                      const SizedBox(height: 12),
                      
                      // Render media if present
                      if (inc['imageUrls'] != null && (inc['imageUrls'] as List).isNotEmpty) ...[
                        const Text('Captured Evidence:', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey)),
                        const SizedBox(height: 6),
                        SizedBox(
                          height: 80,
                          child: ListView.builder(
                            scrollDirection: Axis.horizontal,
                            itemCount: (inc['imageUrls'] as List).length,
                            itemBuilder: (context, idx) {
                              final path = inc['imageUrls'][idx];
                              return Padding(
                                padding: const EdgeInsets.only(right: 8.0),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: path.startsWith('http')
                                      ? Image.network(path, width: 80, height: 80, fit: BoxFit.cover)
                                      : Image.file(File(path), width: 80, height: 80, fit: BoxFit.cover),
                                ),
                              );
                            },
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],

                      if (!isResolved)
                        Align(
                          alignment: Alignment.centerRight,
                          child: ElevatedButton.icon(
                            icon: const Icon(Icons.check),
                            label: const Text('MARK RESOLVED'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: BestieTokens.cBrand,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(BestieTokens.rMd),
                              ),
                            ),
                            onPressed: () async {
                              final ok = await appProvider.resolveIncident(inc['id'].toString());
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      ok
                                          ? 'Incident resolved! Executive notified.'
                                          : (appProvider.lastActionError ?? 'Could not resolve incident.'),
                                    ),
                                    backgroundColor: ok ? BestieTokens.cBrand : BestieTokens.cText,
                                  ),
                                );
                              }
                            },
                          ),
                        )
                    ],
                  ),
                ),
              ),
                const SizedBox(height: 10),
              ];
            }),
        ],
      ),
    );
  }
}

class AdminLiveActivitiesTab extends StatelessWidget {
  const AdminLiveActivitiesTab({super.key});

  @override
  Widget build(BuildContext context) {
    final appProvider = Provider.of<AppProvider>(context);
    final visits = appProvider.adminLiveVisitsList;
    final gpsPings = appProvider.adminLiveGpsList;

    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          const TabBar(
            labelColor: BestieTokens.cBrand,
            unselectedLabelColor: BestieTokens.cTextMuted,
            indicatorColor: BestieTokens.cBrand,
            indicatorWeight: 3,
            tabs: [
              Tab(icon: Icon(Icons.storefront_outlined, size: 20), text: 'Login & Visits'),
              Tab(icon: Icon(Icons.location_on_outlined, size: 20), text: 'GPS Location Pings'),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                _buildVisitsSubTab(context, visits),
                _buildGpsSubTab(context, gpsPings),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVisitsSubTab(BuildContext context, List<dynamic> visits) {
    if (visits.isEmpty) {
      final role = (Provider.of<AppProvider>(context, listen: false).role ?? '').toLowerCase();
      final isSuper = role == 'super_admin' || role == 'superadmin';
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.store_outlined, size: 64, color: BestieTokens.cTextMuted),
              const SizedBox(height: 12),
              const Text('No live visits logged yet.', style: TextStyle(fontWeight: FontWeight.bold, color: BestieTokens.cTextMuted)),
              Text(
                isSuper
                    ? 'Platform super_admin cannot read org Logs on the server (403). Sign in as organisation admin (e.g. Rajesh) to see Farhan/Sunitha attendance and visits.'
                    : 'Executives’ attendance logins and outlet check-ins appear here. Pull to refresh after they start their day.',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 12, color: BestieTokens.cTextMuted),
              ),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () => Provider.of<AppProvider>(context, listen: false).fetchAdminDashboardData(),
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(16, 14, 16, MediaQuery.of(context).padding.bottom + 100),
        itemCount: visits.length,
        separatorBuilder: (_, __) => const SizedBox(height: 14),
        itemBuilder: (context, idx) {
          final visit = visits[idx];
          return _buildVisitLogCard(context, visit);
        },
      ),
    );
  }

  Widget _buildVisitLogCard(BuildContext context, dynamic visit) {
    final checkedOut = visit['checkOutTime'] != null;
    final isDailyLogin = visit['isDailyLogin'] == true;
    final isGpsLive = visit['source']?.toString() == 'gps_live';
    final name = visit['executiveName']?.toString() ?? 'Executive';
    final email = visit['executiveEmail']?.toString() ?? '';
    final initial = name.isNotEmpty ? name.substring(0, 1).toUpperCase() : '?';
    final statusLabel = isGpsLive
        ? 'GPS LIVE'
        : isDailyLogin
        ? 'DAILY LOGIN'
        : (checkedOut ? 'COMPLETED' : 'IN VISIT');
    final hasSelfie = visit['selfieUrl'] != null &&
        visit['selfieUrl'].toString().isNotEmpty &&
        visit['selfieUrl'].toString() != 'auto-detected';
    final address = (visit['address'] ?? visit['outletAddress'] ?? 'Address not resolved').toString();
    final outletName = visit['outletName']?.toString() ?? 'Outlet';
    final phone = visit['outletPhone']?.toString() ?? visit['phone']?.toString() ?? '';
    final remarks = (visit['remarks']?.toString().trim().isNotEmpty == true)
        ? visit['remarks'].toString()
        : '—';

    return _AdminPanelCard(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header: avatar + name/email + outlined status badge
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: BestieTokens.cBrand,
                foregroundColor: Colors.white,
                child: Text(initial, style: const TextStyle(fontWeight: BestieTokens.fwBold, fontSize: 16)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: BestieTokens.fwBold,
                        fontSize: 15,
                        color: BestieTokens.cText,
                      ),
                    ),
                    if (email.isNotEmpty)
                      Text(
                        email,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 11, color: BestieTokens.cTextMuted),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _outlinedStatusBadge(statusLabel),
            ],
          ),
          const SizedBox(height: 12),

          // Activity title row
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                isGpsLive
                    ? Icons.my_location
                    : isDailyLogin
                        ? Icons.login_rounded
                        : Icons.storefront_outlined,
                size: 18,
                color: BestieTokens.cBrand,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isGpsLive
                          ? 'Live GPS update'
                          : isDailyLogin
                              ? 'Daily field login'
                              : outletName,
                      style: const TextStyle(
                        fontWeight: BestieTokens.fwBold,
                        fontSize: 14,
                        color: BestieTokens.cText,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      isGpsLive
                          ? address
                          : isDailyLogin
                          ? address
                          : [
                              if (phone.isNotEmpty) phone,
                              if ((visit['outletAddress'] ?? '').toString().isNotEmpty)
                                visit['outletAddress'].toString(),
                            ].where((e) => e.toString().trim().isNotEmpty).join(' · '),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12, color: BestieTokens.cTextMuted, height: 1.3),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Divider(height: 1, color: BestieTokens.cBorderSoft),
          ),

          // Selfie block
          if (hasSelfie) ...[
            Text(
              isGpsLive
                  ? 'LATEST CHECK-IN SELFIE'
                  : isDailyLogin
                      ? 'DAILY LOGIN SELFIE'
                      : 'CHECK-IN SELFIE',
              style: const TextStyle(
                fontSize: 10,
                fontWeight: BestieTokens.fwBold,
                color: BestieTokens.cTextMuted,
                letterSpacing: 0.4,
              ),
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(BestieTokens.rMd),
              child: _buildVisitSelfieImage(context, visit['selfieUrl'].toString()),
            ),
          ] else if (isGpsLive) ...[
            _noSelfieInfoBanner('Live GPS ping from production'),
          ] else if (isDailyLogin) ...[
            const Text(
              'DAILY LOGIN SELFIE',
              style: TextStyle(
                fontSize: 10,
                fontWeight: BestieTokens.fwBold,
                color: BestieTokens.cTextMuted,
                letterSpacing: 0.4,
              ),
            ),
            const SizedBox(height: 8),
            _selfieUnavailableBox(),
          ] else ...[
            _noSelfieInfoBanner('No selfie attached to this check-in'),
          ],

          const SizedBox(height: 12),

          // Time row
          Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: BestieTokens.cBrandSoft,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(Icons.access_time_rounded, size: 15, color: BestieTokens.cBrand),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: isGpsLive
                            ? 'GPS AT  '
                            : isDailyLogin
                                ? 'LOGIN AT  '
                                : 'CHECK-IN AT  ',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: BestieTokens.fwBold,
                          color: BestieTokens.cTextMuted,
                          letterSpacing: 0.3,
                        ),
                      ),
                      TextSpan(
                        text: _formatTime(visit['checkInTime']?.toString()),
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: BestieTokens.fwBold,
                          color: BestieTokens.cText,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (checkedOut && !isDailyLogin)
                Text.rich(
                  TextSpan(
                    children: [
                      const TextSpan(
                        text: 'CHECK-OUT  ',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: BestieTokens.fwBold,
                          color: BestieTokens.cTextMuted,
                        ),
                      ),
                      TextSpan(
                        text: _formatTime(visit['checkOutTime']?.toString()),
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: BestieTokens.fwBold,
                          color: BestieTokens.cText,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),

          if (!isDailyLogin && (visit['salesValue'] != null)) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                const Text(
                  'ORDER  ',
                  style: TextStyle(fontSize: 10, fontWeight: BestieTokens.fwBold, color: BestieTokens.cTextMuted),
                ),
                Text(
                  '₹${(visit['salesValue'] ?? 0.0).toStringAsFixed(2)}',
                  style: const TextStyle(fontSize: 14, fontWeight: BestieTokens.fwBold, color: BestieTokens.cBrand),
                ),
                if (visit['managerOverride'] == true) ...[
                  const Spacer(),
                  _outlinedStatusBadge('OVERRIDE'),
                ],
              ],
            ),
          ],

          const SizedBox(height: 10),
          Text(
            isGpsLive
                ? 'Activity: Production GPS live ping'
                : isDailyLogin
                ? 'Activity: Daily field login (blink selfie + location)'
                : 'Client Remarks: $remarks',
            style: const TextStyle(
              fontSize: 12,
              fontStyle: FontStyle.italic,
              color: BestieTokens.cTextSoft,
            ),
          ),
          const SizedBox(height: 10),

          // Location footer
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFF3F6FC),
              borderRadius: BorderRadius.circular(BestieTokens.rMd),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.my_location, size: 18, color: BestieTokens.cBrand),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        address,
                        style: const TextStyle(fontSize: 12, fontWeight: BestieTokens.fwBold, color: BestieTokens.cText),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'GPS: ${_formatCoordinate(visit['gpsLat'])}, ${_formatCoordinate(visit['gpsLng'])}',
                        style: const TextStyle(fontSize: 11, color: BestieTokens.cTextMuted),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _outlinedStatusBadge(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: BestieTokens.cBrand.withValues(alpha: 0.55)),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 10,
          fontWeight: BestieTokens.fwBold,
          color: BestieTokens.cBrand,
          letterSpacing: 0.3,
        ),
      ),
    );
  }

  Widget _selfieUnavailableBox() {
    return CustomPaint(
      painter: const _DashedBorderPainter(color: BestieTokens.cBorder),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 22),
        alignment: Alignment.center,
        child: const Column(
          children: [
            Icon(Icons.photo_camera_outlined, size: 28, color: BestieTokens.cTextMuted),
            SizedBox(height: 6),
            Text(
              'Selfie unavailable',
              style: TextStyle(fontSize: 12, color: BestieTokens.cTextMuted, fontWeight: BestieTokens.fwSemibold),
            ),
          ],
        ),
      ),
    );
  }

  Widget _noSelfieInfoBanner(String message) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: BestieTokens.cBrandSoft,
        borderRadius: BorderRadius.circular(BestieTokens.rMd),
        border: Border.all(color: BestieTokens.cBrand.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline, size: 18, color: BestieTokens.cBrand),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: BestieTokens.fwSemibold,
                color: BestieTokens.cBrandStrong,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGpsSubTab(BuildContext context, List<dynamic> gpsPings) {
    if (gpsPings.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.location_off_outlined, size: 64, color: BestieTokens.cTextMuted),
              SizedBox(height: 12),
              Text('No executive GPS logs yet.', style: TextStyle(fontWeight: FontWeight.bold, color: BestieTokens.cTextMuted)),
              Text(
                'When field executives login and move, their check-in locations and GPS pings appear here. Pull to refresh after executives start their day.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: BestieTokens.cTextMuted),
              ),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () => Provider.of<AppProvider>(context, listen: false).fetchAdminLiveGpsList(),
      child: ListView.separated(
        padding: EdgeInsets.fromLTRB(16, 14, 16, MediaQuery.of(context).padding.bottom + 100),
        itemCount: gpsPings.length,
        separatorBuilder: (_, __) => const SizedBox(height: 14),
        itemBuilder: (context, idx) {
          final ping = gpsPings[idx];
          final lat = _formatCoordinate(ping['latitude']);
          final lng = _formatCoordinate(ping['longitude']);
          final name = ping['executiveName']?.toString() ?? 'Executive';
          final email = ping['executiveEmail']?.toString() ?? '';
          final initial = name.isNotEmpty ? name.substring(0, 1).toUpperCase() : '?';
          final address = (ping['address']?.toString().trim().isNotEmpty == true)
              ? ping['address'].toString()
              : 'Resolving location…';
          final source = ping['startPoint']?.toString() ?? ping['source']?.toString() ?? 'TRACKING';
          final deviceId = ping['deviceId']?.toString() ?? '';
          return _AdminPanelCard(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
            onTap: () async {
              final la = double.tryParse(ping['latitude']?.toString() ?? '');
              final lo = double.tryParse(ping['longitude']?.toString() ?? '');
              if (la == null || lo == null) return;
              final uri = Uri.parse('https://www.google.com/maps/search/?api=1&query=$la,$lo');
              await launchUrl(uri, mode: LaunchMode.externalApplication);
            },
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      radius: 20,
                      backgroundColor: BestieTokens.cBrand,
                      foregroundColor: Colors.white,
                      child: Text(initial, style: const TextStyle(fontWeight: BestieTokens.fwBold)),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(name, style: const TextStyle(fontWeight: BestieTokens.fwBold, fontSize: 15)),
                          if (email.isNotEmpty)
                            Text(email, style: const TextStyle(fontSize: 11, color: BestieTokens.cTextMuted)),
                        ],
                      ),
                    ),
                    _outlinedStatusBadge(source.toUpperCase()),
                  ],
                ),
                const SizedBox(height: 10),
                Text(address, style: const TextStyle(fontSize: 13, color: BestieTokens.cText)),
                const SizedBox(height: 6),
                Text(
                  'GPS: $lat, $lng',
                  style: const TextStyle(fontSize: 12, color: BestieTokens.cTextMuted),
                ),
                if (deviceId.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Device: ${deviceId.length > 18 ? '${deviceId.substring(0, 18)}…' : deviceId}',
                    style: const TextStyle(fontSize: 11, color: BestieTokens.cTextMuted),
                  ),
                ],
                const SizedBox(height: 4),
                Text(
                  _formatTime(ping['timestamp']?.toString()),
                  style: const TextStyle(fontSize: 11, color: BestieTokens.cTextMuted),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  String _formatTime(String? isoString) {
    if (isoString == null) return '--:--';
    try {
      final dt = DateTime.parse(isoString).toLocal();
      return DateFormat('hh:mm a').format(dt);
    } catch (_) {
      return isoString;
    }
  }

  String _formatCoordinate(dynamic value) {
    final parsed = double.tryParse(value?.toString() ?? '');
    if (parsed == null) return '--';
    return parsed.toStringAsFixed(6);
  }

  Widget _buildVisitSelfieImage(BuildContext context, String url) {
    const height = 160.0;
    final token = context.read<AppProvider>().authToken;
    final trimmedUrl = url.trim();

    Widget frame(Widget child) => ClipRRect(
          borderRadius: BorderRadius.circular(BestieTokens.rMd),
          child: SizedBox(width: double.infinity, height: height, child: child),
        );

    Widget fallback() => SizedBox(height: height, child: _selfieUnavailableBox());

    Uint8List? decodeDataUri(String raw) {
      try {
        final b64 = raw.contains(',') ? raw.split(',').last : raw;
        if (b64.length < 64) return null;
        return base64Decode(b64);
      } catch (_) {
        return null;
      }
    }

    if (trimmedUrl.startsWith('data:image')) {
      final bytes = decodeDataUri(trimmedUrl);
      if (bytes == null) return fallback();
      return frame(
        Image.memory(
          bytes,
          height: height,
          width: double.infinity,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => fallback(),
        ),
      );
    }

    final possibleRawBase64 = trimmedUrl.isNotEmpty &&
        !trimmedUrl.startsWith('http://') &&
        !trimmedUrl.startsWith('https://') &&
        !trimmedUrl.startsWith('/') &&
        !trimmedUrl.contains(r'\') &&
        !RegExp(r'[/\\.]').hasMatch(trimmedUrl) &&
        trimmedUrl.length > 100;
    if (possibleRawBase64) {
      try {
        final bytes = base64Decode(trimmedUrl);
        return frame(
          Image.memory(
            bytes,
            height: height,
            width: double.infinity,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => fallback(),
          ),
        );
      } catch (_) {}
    }

    String networkUrl = trimmedUrl;
    if (networkUrl.startsWith('/')) {
      networkUrl = '${ApiEndpoints.baseUrl}$networkUrl';
    } else if (!networkUrl.startsWith('http://') &&
        !networkUrl.startsWith('https://') &&
        !File(networkUrl).existsSync()) {
      networkUrl = '${ApiEndpoints.baseUrl}/$networkUrl';
    }

    if (networkUrl.startsWith('http://') || networkUrl.startsWith('https://')) {
      final headers = (token == null || token.isEmpty) ? null : {'Authorization': 'Bearer $token'};
      return frame(
        Image.network(
          networkUrl,
          height: height,
          width: double.infinity,
          fit: BoxFit.cover,
          headers: headers,
          loadingBuilder: (context, child, progress) {
            if (progress == null) return child;
            return const Center(child: CircularProgressIndicator(strokeWidth: 2));
          },
          errorBuilder: (_, __, ___) {
            // Retry without auth — some upload CDNs are public.
            return Image.network(
              networkUrl,
              height: height,
              width: double.infinity,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => fallback(),
            );
          },
        ),
      );
    }

    final file = File(trimmedUrl);
    if (file.existsSync()) {
      return frame(
        Image.file(
          file,
          height: height,
          width: double.infinity,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => fallback(),
        ),
      );
    }
    return fallback();
  }
}

class _DashedBorderPainter extends CustomPainter {
  final Color color;
  const _DashedBorderPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke;

    const dashWidth = 5.0;
    const dashSpace = 4.0;
    final rect = Offset.zero & size;

    void drawDashedLine(Offset start, Offset end) {
      final total = (end - start).distance;
      if (total == 0) return;
      final direction = (end - start) / total;
      var drawn = 0.0;
      while (drawn < total) {
        final from = start + direction * drawn;
        final toLen = (drawn + dashWidth).clamp(0.0, total);
        final to = start + direction * toLen;
        canvas.drawLine(from, to, paint);
        drawn += dashWidth + dashSpace;
      }
    }

    drawDashedLine(rect.topLeft, rect.topRight);
    drawDashedLine(rect.topRight, rect.bottomRight);
    drawDashedLine(rect.bottomRight, rect.bottomLeft);
    drawDashedLine(rect.bottomLeft, rect.topLeft);
  }

  @override
  bool shouldRepaint(covariant _DashedBorderPainter oldDelegate) => oldDelegate.color != color;
}
