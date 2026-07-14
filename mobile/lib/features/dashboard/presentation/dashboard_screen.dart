import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/network/app_provider.dart';
import 'package:intl/intl.dart';
import 'package:image_picker/image_picker.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' as latlong;
import 'package:url_launcher/url_launcher.dart';

import '../../telecaller/presentation/telecaller_screen.dart';

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
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Visit auto-registered at $outletName after minimum stay time.'),
        backgroundColor: Colors.green,
      ),
    );

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

    return Scaffold(
      appBar: AppBar(
        title: Text(_currentIndex == 0
            ? 'Executive Home'
            : _currentIndex == 1
                ? 'Route & Tracking'
                : _currentIndex == 2
                    ? 'New Customer Prospects'
                    : 'Field Reports'),
        actions: [
          // Synchronize button
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
          // Logout button
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Logout',
            onPressed: () => appProvider.logout('mock-device-fingerprint-123456'),
          ),
        ],
      ),
      body: Stack(
        children: [
          tabs[_currentIndex],
          
          // Persistent Break Widget at the bottom (Fulfills Module 2 global break system requirement)
          if (appProvider.attendanceStatus == 'LOGGED_IN' || appProvider.attendanceStatus == 'PRESENT')
            Positioned(
              right: 16,
              bottom: 16,
              child: FloatingActionButton.extended(
                backgroundColor: appProvider.activeBreak != null ? Colors.red : const Color(0xFFF59E0B),
                foregroundColor: Colors.white,
                icon: Icon(appProvider.activeBreak != null ? Icons.pause_circle_filled : Icons.free_breakfast),
                label: Text(appProvider.activeBreak != null ? 'End Break' : 'Take Break'),
                onPressed: () {
                  if (appProvider.activeBreak != null) {
                    _showEndBreakDialog(context, appProvider);
                  } else {
                    _showStartBreakDialog(context, appProvider);
                  }
                },
              ),
            ),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) {
          setState(() {
            _currentIndex = index;
          });
        },
        type: BottomNavigationBarType.fixed,
        selectedItemColor: const Color(0xFF1E3A8A),
        unselectedItemColor: Colors.grey,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.dashboard_outlined),
            activeIcon: Icon(Icons.dashboard),
            label: 'Home',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.map_outlined),
            activeIcon: Icon(Icons.map),
            label: 'Route',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.explore_outlined),
            activeIcon: Icon(Icons.explore),
            label: 'Prospects',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.report_problem_outlined),
            activeIcon: Icon(Icons.report_problem),
            label: 'Reports',
          ),
        ],
      ),
    );
  }

  void _showStartBreakDialog(BuildContext context, AppProvider provider) {
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
                'Select Break Category',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF1E3A8A)),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              ListTile(
                leading: const Icon(Icons.coffee, color: Colors.brown),
                title: const Text('Coffee Break'),
                onTap: () {
                  provider.startBreakSession('COFFEE');
                  Navigator.pop(context);
                },
              ),
              ListTile(
                leading: const Icon(Icons.restaurant, color: Colors.orange),
                title: const Text('Lunch Break'),
                onTap: () {
                  provider.startBreakSession('LUNCH');
                  Navigator.pop(context);
                },
              ),
              ListTile(
                leading: const Icon(Icons.person_pin, color: Colors.blue),
                title: const Text('Personal Break'),
                onTap: () {
                  provider.startBreakSession('PERSONAL');
                  Navigator.pop(context);
                },
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

  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (context) {
      return StatefulBuilder(
        builder: (context, setModalState) {
          double bottomInset = MediaQuery.of(context).viewInsets.bottom;

          return Container(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.85,
            ),
            child: SingleChildScrollView(
              padding: EdgeInsets.only(
                bottom: bottomInset + 24,
                left: 16,
                right: 16,
                top: 24,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text('Products Used / Order & Remarks', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF1E3A8A)), textAlign: TextAlign.center),
                  const SizedBox(height: 16),
                  const Text('SELECT PRODUCTS THIS CUSTOMER USES OR ORDERS', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey)),
                  const SizedBox(height: 4),
                  Container(
                    height: 160,
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey[300]!),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: provider.productCatalog.length,
                      itemBuilder: (context, idx) {
                        final prod = provider.productCatalog[idx];
                        double displayPrice = 0.0;
                        if (prod['unitPrice'] != null) {
                          displayPrice = double.tryParse(prod['unitPrice'].toString()) ?? 0.0;
                        }
                        return ListTile(
                          dense: true,
                          title: Text(prod['name'] ?? 'Test Product SKU', style: const TextStyle(fontWeight: FontWeight.bold)),
                          subtitle: Text('SKU: ${prod['sku']} - \$${displayPrice.toStringAsFixed(2)}'),
                          trailing: IconButton(
                            icon: const Icon(Icons.add_circle, color: Color(0xFF1E3A8A), size: 20),
                            onPressed: () {
                              provider.addProductToOrder(prod['sku'] ?? 'SKU-GEN', prod['name'] ?? 'Test Product', 1, displayPrice);
                              setModalState(() {});
                            },
                          ),
                        );
                      },
                    ),
                  ),
                  const Divider(height: 24),
                  const Text('Selected Products / Order Items:', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  if (provider.currentOrderItems.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: Text('No products selected. You can still submit remarks for follow-up tracking.', style: TextStyle(color: Colors.grey, fontStyle: FontStyle.italic, fontSize: 13)),
                    ),
                  ...provider.currentOrderItems.map((item) {
                    double unitP = 0.0;
                    if (item['unitPrice'] != null) {
                      unitP = double.tryParse(item['unitPrice'].toString()) ?? 0.0;
                    }
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4.0),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(child: Text(item['name'] ?? 'Product', style: const TextStyle(fontSize: 13))),
                          Row(
                            children: [
                              IconButton(
                                icon: const Icon(Icons.remove_circle_outline, size: 20, color: Colors.red),
                                onPressed: () {
                                  provider.updateProductQty(item['sku'], item['qty'] - 1);
                                  setModalState(() {});
                                },
                              ),
                              Text('${item['qty']}', style: const TextStyle(fontWeight: FontWeight.bold)),
                              IconButton(
                                icon: const Icon(Icons.add_circle_outline, size: 20, color: Colors.green),
                                onPressed: () {
                                  provider.updateProductQty(item['sku'], item['qty'] + 1);
                                  setModalState(() {});
                                },
                              ),
                              const SizedBox(width: 8),
                              Text('\$${(unitP * item['qty']).toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.bold)),
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
                      Text('\$${provider.currentOrderTotal.toStringAsFixed(2)}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF1E3A8A))),
                    ],
                  ),
                  const SizedBox(height: 16),
                  const Text('Quick Remarks:', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey)),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      'Next Visit',
                      'Payment received',
                      'Payment pending',
                      'Order placed last week',
                      'Visit again next week',
                    ].map((remark) {
                      return ActionChip(
                        label: Text(remark, style: const TextStyle(fontSize: 11)),
                        onPressed: () {
                          final current = remarksController.text.trim();
                          remarksController.text = current.isEmpty ? remark : '$current; $remark';
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
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () async {
                      final hasProducts = provider.currentOrderItems.isNotEmpty;
                      final hasRemarks = remarksController.text.trim().isNotEmpty;
                      if (!hasProducts && !hasRemarks) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Add at least one product or a remark before submitting.'), backgroundColor: Colors.orange),
                        );
                        return;
                      }

                      final success = await provider.submitOrder(remarksController.text.trim());
                      if (success && context.mounted) {
                        Navigator.pop(context);
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Visit products/remarks saved successfully!'), backgroundColor: Colors.green),
                        );
                      }
                    },
                    child: const Text('SAVE PRODUCTS / REMARKS'),
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

class HomeTab extends StatelessWidget {
  const HomeTab({super.key});

  @override
  Widget build(BuildContext context) {
    final appProvider = Provider.of<AppProvider>(context);
    final isWorking = appProvider.attendanceStatus == 'LOGGED_IN' || appProvider.attendanceStatus == 'PRESENT';
    final hasCheckedOut = appProvider.attendanceCheckOutAt != null;

    return SingleChildScrollView(
      padding: const EdgeInsets.only(bottom: 80), // extra padding for global break button
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 1. Attendance & Hours Card (Real-time tracking, Module 1 & 2)
          Card(
            color: const Color(0xFF1E3A8A),
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
                          const Text('Status', style: TextStyle(color: Colors.white60, fontSize: 12)),
                          Text(
                            appProvider.activeBreak != null
                                ? 'ON BREAK (${appProvider.activeBreak!['breakType']})'
                                : isWorking
                                    ? 'WORKING'
                                    : hasCheckedOut
                                        ? 'CHECKED OUT'
                                        : 'ABSENT',
                            style: const TextStyle(color: Color(0xFFF59E0B), fontSize: 14, fontWeight: FontWeight.bold),
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

          // 2. Progress Bar (Module 4)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Today\'s Route Progress', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF1E3A8A))),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Visits: ${appProvider.completedVisitsCount} / ${appProvider.plannedVisitsCount}'),
                      Text('${appProvider.planProgressPercentage.toStringAsFixed(1)}%'),
                    ],
                  ),
                  const SizedBox(height: 8),
                  LinearProgressIndicator(
                    value: appProvider.planProgressPercentage / 100.0,
                    minHeight: 12,
                    borderRadius: BorderRadius.circular(6),
                    backgroundColor: Colors.grey[200],
                    valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF1E3A8A)),
                  ),
                ],
              ),
            ),
          ),

          if (appProvider.todayPlan != null && appProvider.activeVisit == null)
            Card(
              color: Colors.green.shade50,
              child: ListTile(
                leading: Icon(Icons.gps_fixed, color: Colors.green.shade700),
                title: const Text('Auto visit monitoring active', style: TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text(
                  'Stay within 100m of an outlet for ${appProvider.minimumVisitDurationMinutes} min to auto-register a visit.',
                ),
              ),
            ),

          // 3. Daily Area Selector (If no plan active, Module 4)
          if (appProvider.todayPlan == null)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Configure Your Day', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF1E3A8A))),
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

          // 4. Planned Outlets Checklist (Module 4 & 5)
          if (appProvider.todayPlan != null) ...[
            Padding(
              padding: const EdgeInsets.only(left: 16, top: 16, right: 16, bottom: 8),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'TODAY\'S TARGET OUTLETS',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.grey),
                    ),
                  ),
                  TextButton.icon(
                    icon: const Icon(Icons.add_business, size: 18),
                    label: const Text('ADD OUTLET'),
                    onPressed: () => _showAddManualOutletSheet(context, appProvider),
                  ),
                ],
              ),
            ),
            ...appProvider.plannedOutlets.map((outlet) {
              final isCompleted = outlet['visitStatus'] == 'COMPLETED';

              return Card(
                color: isCompleted ? Colors.green[50] : Colors.white,
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: isCompleted ? Colors.green : const Color(0xFF1E3A8A),
                    foregroundColor: Colors.white,
                    child: Icon(isCompleted ? Icons.check : Icons.store),
                  ),
                  title: Text(outlet['name'], style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text(outlet['address']),
                  trailing: Icon(
                    isCompleted ? Icons.check_circle : Icons.arrow_forward_ios_outlined,
                    color: isCompleted ? Colors.green : Colors.grey,
                    size: 20,
                  ),
                  onTap: () {
                    _showOutletWorkflowDialog(context, appProvider, outlet);
                  },
                ),
              );
            }),
          ]
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
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF1E3A8A)),
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
                  leading: const Icon(Icons.map, color: Color(0xFF1E3A8A)),
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
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF1E3A8A)),
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
    final latController = TextEditingController();
    final lngController = TextEditingController();

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
                  'Add Outlet to Today\'s Plan',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF1E3A8A)),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(
                    labelText: 'Outlet Name',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.storefront),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: addressController,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'Outlet Address',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.place),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: latController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Latitude (manual override)',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: lngController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Longitude (manual override)',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                const Text(
                  'Location is mandatory. The app will use exact lat/lng, address lookup, or your current GPS as fallback.',
                  style: TextStyle(fontSize: 11, color: Colors.grey),
                ),
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  icon: const Icon(Icons.add_business),
                  label: const Text('ADD OUTLET'),
                  onPressed: () async {
                    final name = nameController.text.trim();
                    final address = addressController.text.trim();
                    if (name.isEmpty || address.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Outlet name and address are required.'), backgroundColor: Colors.red),
                      );
                      return;
                    }

                    final targetLocation = await _resolveOutletTargetLocation(
                      address,
                      manualLat: double.tryParse(latController.text.trim()),
                      manualLng: double.tryParse(lngController.text.trim()),
                    );
                    if (!context.mounted) return;

                    if (targetLocation == null) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Could not get outlet location. Turn on GPS or enter exact latitude and longitude.'), backgroundColor: Colors.red),
                      );
                      return;
                    }

                    await provider.addManualOutletToTodayPlan(
                      name,
                      address,
                      latitude: targetLocation.latitude,
                      longitude: targetLocation.longitude,
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
  }

  void _showOutletWorkflowDialog(BuildContext context, AppProvider provider, Map<String, dynamic> outlet) async {
    await provider.restoreActiveVisitForOutlet(outlet['id']?.toString() ?? '');
    await provider.restoreActiveVisitFromLocalDb();
    if (!context.mounted) return;

    showDialog(
      context: context,
      builder: (context) {
        final isCompleted = outlet['visitStatus'] == 'COMPLETED';
        final activeVisit = provider.activeVisit;
        final isThisOutletActive = activeVisit != null &&
            activeVisit['outletId']?.toString() == outlet['id']?.toString();
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
                future: provider.getOutletVisitHistory(outlet['id']?.toString() ?? ''),
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
                        Text('Products: $productText', style: const TextStyle(fontSize: 12, color: Color(0xFF1E3A8A))),
                      ],
                    ),
                  );
                },
              ),
              const SizedBox(height: 16),
              if (!isCompleted && activeVisit == null)
                const Text('To start the visit checklist, you must first check in at the outlet.'),
              if (isThisOutletActive)
                const Text('Active Visit Session Running. You can submit orders and checkout now.'),
              if (hasOtherActiveVisit)
                const Text('Another outlet visit is currently active. Please check out there before starting a new visit.'),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('CLOSE'),
            ),
            if (!isCompleted && activeVisit == null)
              ElevatedButton.icon(
                icon: const Icon(Icons.gps_fixed),
                label: const Text('CHECK-IN (100M GEOFENCE)'),
                onPressed: () async {
                  Navigator.pop(context);
                  _runCheckInFlow(context, provider, outlet);
                },
              ),
            if (isThisOutletActive) ...[
              ElevatedButton.icon(
                icon: const Icon(Icons.add_shopping_cart),
                label: const Text('ORDER / REMARKS'),
                onPressed: () {
                  Navigator.pop(context);
                showOrderCatalogScreen(context, provider);
                },
              ),
              ElevatedButton.icon(
                icon: const Icon(Icons.directions_walk),
                label: const Text('CHECK-OUT'),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
                onPressed: () async {
                  await provider.checkoutOutlet();
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
    // 1. Fetch mandatory physical location of the executive using device GPS (Module 5 Check-In)
    double executiveLat;
    double executiveLng;
    String executiveAddress;

    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Turn on Location Services. GPS is mandatory for selfie check-in.'),
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
              content: Text('Location permission is required before taking a check-in selfie.'),
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

    // 2. Required selfie check-in using device camera (Module 5)
    final ImagePicker picker = ImagePicker();
    XFile? photo;
    try {
      photo = await picker.pickImage(source: ImageSource.camera, preferredCameraDevice: CameraDevice.front);
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
          const SnackBar(content: Text('Selfie capture is mandatory to complete Check-In.'), backgroundColor: Colors.orange),
        );
      }
      return;
    }

    // Check in with accurate selfie and verified GPS location
    final result = await provider.checkInOutlet(
      outlet['id'],
      executiveLat,
      executiveLng,
      photo.path,
      address: executiveAddress,
    );

    if (context.mounted && result != null) {
      if (result['requiresOutletLocation'] == true) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(result['message'] ?? 'Outlet target location is required.'), backgroundColor: Colors.red),
        );
      } else if (result['requiresOverride'] == true) {
        _showGeofenceOverrideDialog(context, provider, outlet, result['distanceMeters'] ?? 0.0, photo.path, executiveLat, executiveLng, executiveAddress);
      } else if (result['success'] == true && result['visit'] != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Checked in successfully with accurate GPS & Selfie! Visit checklist active.'), backgroundColor: Colors.green),
        );
        showActiveVisitActionsDialog(context, provider, outlet);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Check-in was not completed. Please try again.'), backgroundColor: Colors.red),
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
class MapTrackingTab extends StatefulWidget {
  const MapTrackingTab({super.key});

  @override
  State<MapTrackingTab> createState() => _MapTrackingTabState();
}

class _MapTrackingTabState extends State<MapTrackingTab> {
  latlong.LatLng? _currentPosition;
  final MapController _mapController = MapController();

  @override
  void initState() {
    super.initState();
    _loadCurrentPosition();
  }

  Future<void> _loadCurrentPosition() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return;
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) return;

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 10),
        ),
      );
      if (!mounted) return;
      setState(() {
        _currentPosition = latlong.LatLng(position.latitude, position.longitude);
      });
    } catch (_) {
      // Keep map usable with outlet markers even if current location is unavailable.
    }
  }

  @override
  Widget build(BuildContext context) {
    final appProvider = Provider.of<AppProvider>(context);
    final markers = _buildMarkers(context, appProvider);
    final polylinePoints = _buildOutletPoints(appProvider);
    final initialTarget = _initialMapTarget(appProvider);

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // GPS Odometer card (Module 3)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  Column(
                    children: [
                      const Text('Total Distance', style: TextStyle(color: Colors.grey)),
                      Text('${appProvider.totalDistanceCoveredKm.toStringAsFixed(2)} KM', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF1E3A8A))),
                    ],
                  ),
                  const SizedBox(height: 40, child: VerticalDivider()),
                  Column(
                    children: [
                      const Text('Odometer Start', style: TextStyle(color: Colors.grey)),
                      DropdownButton<String>(
                        value: appProvider.odometerStartPoint,
                        onChanged: (val) {
                          if (val != null) appProvider.setOdometerStartPoint(val);
                        },
                        items: const [
                          DropdownMenuItem(value: 'HOME', child: Text('Home Location')),
                          DropdownMenuItem(value: 'FIRST_OUTLET', child: Text('First Outlet')),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          // Leaflet/OpenStreetMap representation area (Module 3, 4 & 8)
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Stack(
                children: [
                  FlutterMap(
                    mapController: _mapController,
                    options: MapOptions(
                      initialCenter: initialTarget,
                      initialZoom: markers.isEmpty ? 12 : 14,
                    ),
                    children: [
                      TileLayer(
                        urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                        userAgentPackageName: 'com.fieldforce.mobile',
                      ),
                      if (polylinePoints.length > 1)
                        PolylineLayer(
                          polylines: [
                            Polyline(
                              points: polylinePoints,
                              color: const Color(0xFF1E3A8A),
                              strokeWidth: 4,
                            ),
                          ],
                        ),
                      MarkerLayer(markers: markers),
                    ],
                  ),
                  if (markers.isEmpty)
                    Positioned(
                      left: 12,
                      right: 12,
                      top: 12,
                      child: Card(
                        color: Colors.white.withValues(alpha: 0.94),
                        child: const Padding(
                          padding: EdgeInsets.all(12.0),
                          child: Text(
                            'No outlet markers yet. Add/select a route with outlet locations to view them on the map.',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 12, color: Colors.grey),
                          ),
                        ),
                      ),
                    ),
                  Positioned(
                    right: 12,
                    bottom: 12,
                    child: FloatingActionButton.small(
                      heroTag: 'route-map-location',
                      backgroundColor: Colors.white,
                      foregroundColor: const Color(0xFF1E3A8A),
                      onPressed: _currentPosition == null
                          ? _loadCurrentPosition
                          : () => _mapController.move(_currentPosition!, 16),
                      child: const Icon(Icons.my_location),
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          // Route optimization button (Module 8)
          ElevatedButton.icon(
            icon: const Icon(Icons.settings_suggest),
            label: const Text('INTELLIGENT ROUTE OPTIMIZATION'),
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFF59E0B)),
            onPressed: () {
              _showRouteOptimizationScreen(context, appProvider);
            },
          ),
          const SizedBox(height: 60), // Space for break button
        ],
      ),
    );
  }

  latlong.LatLng _initialMapTarget(AppProvider provider) {
    if (_currentPosition != null) return _currentPosition!;
    for (final outlet in provider.plannedOutlets) {
      final lat = double.tryParse(outlet['latitude']?.toString() ?? '');
      final lng = double.tryParse(outlet['longitude']?.toString() ?? '');
      if (lat != null && lng != null) return latlong.LatLng(lat, lng);
    }
    return const latlong.LatLng(28.6139, 77.2090); // New Delhi fallback
  }

  List<latlong.LatLng> _buildOutletPoints(AppProvider provider) {
    return provider.plannedOutlets
        .map((outlet) {
          final lat = double.tryParse(outlet['latitude']?.toString() ?? '');
          final lng = double.tryParse(outlet['longitude']?.toString() ?? '');
          if (lat == null || lng == null) return null;
          return latlong.LatLng(lat, lng);
        })
        .whereType<latlong.LatLng>()
        .toList();
  }

  List<Marker> _buildMarkers(BuildContext context, AppProvider provider) {
    final markers = <Marker>[];

    if (_currentPosition != null) {
      markers.add(
        Marker(
          point: _currentPosition!,
          width: 44,
          height: 44,
          child: const Icon(Icons.my_location, color: Colors.blue, size: 34),
        ),
      );
    }

    for (final outlet in provider.plannedOutlets) {
      final lat = double.tryParse(outlet['latitude']?.toString() ?? '');
      final lng = double.tryParse(outlet['longitude']?.toString() ?? '');
      if (lat == null || lng == null) continue;

      markers.add(
        Marker(
          point: latlong.LatLng(lat, lng),
          width: 52,
          height: 52,
          child: GestureDetector(
            onTap: () => _showOutletMapActions(context, outlet),
            child: const Icon(Icons.location_on, color: Color(0xFFE11D48), size: 42),
          ),
        ),
      );
    }

    return markers;
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
          title: const Text('Generate Optimized Path (Module 8)'),
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
                  if (!await Geolocator.isLocationServiceEnabled()) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Please turn on location services to optimize the route.'), backgroundColor: Colors.orange),
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
                        const SnackBar(content: Text('Location permission is required for route optimization.'), backgroundColor: Colors.orange),
                      );
                    }
                    return;
                  }

                  position = await Geolocator.getCurrentPosition(
                    locationSettings: const LocationSettings(
                      accuracy: LocationAccuracy.high,
                      timeLimit: Duration(seconds: 10),
                    ),
                  );
                } catch (_) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Unable to fetch current GPS location. Please try again.'), backgroundColor: Colors.red),
                    );
                  }
                  return;
                }
                
                final success = await provider.generateOptimizedRoute(
                  provider.plannedOutlets.map((o) => o['id']?.toString() ?? '').where((id) => id.isNotEmpty).toList(),
                  [],
                  position.latitude,
                  position.longitude,
                );

                if (success && context.mounted) {
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

// ---------------- SMART LEAD GENERATION TAB ----------------
class LeadsTab extends StatefulWidget {
  const LeadsTab({super.key});

  @override
  State<LeadsTab> createState() => _LeadsTabState();
}

class _LeadsTabState extends State<LeadsTab> {
  String _selectedCategory = 'retail_store';
  bool _isSearching = false;
  String? _searchError;

  Future<void> _searchNearbyLeads(AppProvider provider) async {
    setState(() {
      _isSearching = true;
      _searchError = null;
    });

    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        setState(() {
          _searchError = 'Turn on GPS/location services to search nearby shops.';
          _isSearching = false;
        });
        return;
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
        setState(() {
          _searchError = 'Location permission is required to find nearby prospects.';
          _isSearching = false;
        });
        return;
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 12),
        ),
      );
      await provider.findNearbyLeads(position.latitude, position.longitude, _selectedCategory);
    } catch (e) {
      setState(() {
        _searchError = 'Could not read your GPS location. Try again outdoors.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isSearching = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final appProvider = Provider.of<AppProvider>(context);

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Card(
            color: Colors.blue.shade50,
            child: const Padding(
              padding: EdgeInsets.all(12.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('What are Prospects?', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF1E3A8A))),
                  SizedBox(height: 6),
                  Text(
                    'These are new shops or businesses near you that are NOT yet in your route. '
                    'When you find a good shop, save it here and follow up later to add it as a regular outlet.',
                    style: TextStyle(fontSize: 13, color: Colors.black87),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          // Category selector rows (Module 7)
          Row(
            children: [
              const Text('Filter:', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(width: 8),
              Expanded(
                child: DropdownButton<String>(
                  value: _selectedCategory,
                  isExpanded: true,
                  onChanged: (val) {
                    if (val != null) {
                      setState(() {
                        _selectedCategory = val;
                      });
                      _searchNearbyLeads(appProvider);
                    }
                  },
                  items: const [
                    DropdownMenuItem(value: 'retail_store', child: Text('Retail Stores')),
                    DropdownMenuItem(value: 'supermarket', child: Text('Supermarkets')),
                    DropdownMenuItem(value: 'restaurant', child: Text('Restaurants')),
                    DropdownMenuItem(value: 'pharmacy', child: Text('Pharmacies')),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: _isSearching
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.gps_fixed, color: Color(0xFF1E3A8A)),
                onPressed: _isSearching ? null : () => _searchNearbyLeads(appProvider),
              ),
            ],
          ),

          const SizedBox(height: 12),

          const Text('NEARBY NEW SHOPS (NOT ON YOUR ROUTE YET)', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey)),
          const SizedBox(height: 4),
          if (_searchError != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8.0),
              child: Text(_searchError!, style: const TextStyle(color: Colors.orange, fontSize: 12)),
            ),

          Expanded(
            child: appProvider.nearbyLeads.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.storefront_outlined, size: 48, color: Colors.grey),
                        const SizedBox(height: 8),
                        const Text(
                          'No nearby prospects found yet.',
                          style: TextStyle(color: Colors.grey),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'Tap SEARCH NOW to scan shops near your current GPS location.',
                          style: TextStyle(color: Colors.grey, fontSize: 12),
                          textAlign: TextAlign.center,
                        ),
                        TextButton(
                          onPressed: _isSearching ? null : () => _searchNearbyLeads(appProvider),
                          child: const Text('SEARCH NOW'),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    itemCount: appProvider.nearbyLeads.length,
                    itemBuilder: (context, idx) {
                      final lead = appProvider.nearbyLeads[idx];

                      return Card(
                        child: ListTile(
                          title: Text(lead['businessName']),
                          subtitle: Text('Distance: ${lead['distanceMeters']}m | Category: ${lead['businessCategory']}'),
                          trailing: IconButton(
                            icon: const Icon(Icons.bookmark_add_outlined, color: Color(0xFF1E3A8A)),
                            tooltip: 'Save as Lead',
                            onPressed: () async {
                              final success = await appProvider.saveLeadRecord(
                                lead['businessName'],
                                lead['businessCategory'],
                                lead['contactPhone'] ?? '',
                                lead['contactEmail'] ?? '',
                                lead['gpsLat'],
                                lead['gpsLng'],
                              );
                              if (success && context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Lead saved to follow-up list!'), backgroundColor: Colors.green),
                                );
                              }
                            },
                          ),
                        ),
                      );
                    },
                  ),
          ),

          const Divider(),
          const Text('MY SAVED PROSPECTS FOR FOLLOW-UP', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey)),
          const SizedBox(height: 4),

          Expanded(
            child: appProvider.savedLeads.isEmpty
                ? const Center(child: Text('No saved prospects yet. Save shops from nearby search results.', style: TextStyle(color: Colors.grey, fontSize: 12)))
                : ListView.builder(
                    itemCount: appProvider.savedLeads.length,
                    itemBuilder: (context, idx) {
                      final sl = appProvider.savedLeads[idx];
                      final isConverted = sl['leadStatus'] == 'CONVERTED';

                      return Card(
                        color: isConverted ? Colors.green[50] : Colors.white,
                        child: ListTile(
                          title: Text(sl['businessName']),
                          subtitle: Text('Status: ${sl['leadStatus']}'),
                          trailing: isConverted
                              ? const Icon(Icons.check_circle, color: Colors.green)
                              : TextButton.icon(
                                  icon: const Icon(Icons.add_home_work, size: 16),
                                  label: const Text('CONVERT'),
                                  onPressed: () async {
                                    final success = await appProvider.convertLeadToOutlet(sl['id']);
                                    if (success && context.mounted) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(content: Text('Lead converted to outlet master!'), backgroundColor: Colors.green),
                                      );
                                    }
                                  },
                                ),
                        ),
                      );
                    },
                  ),
          ),
          const SizedBox(height: 60), // extra padding for global break button
        ],
      ),
    );
  }
}

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
            const SnackBar(content: Text('Incident reported with actual captured media! Manager alert sent via FCM.'), backgroundColor: Colors.orange),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final appProvider = Provider.of<AppProvider>(context);

    return SingleChildScrollView(
      padding: const EdgeInsets.only(left: 16, right: 16, top: 16, bottom: 80),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Card(
            color: Colors.orange.shade50,
            child: const Padding(
              padding: EdgeInsets.all(12.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('What are Field Reports?', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF1E3A8A))),
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
                    const Text('Report a Field Problem', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF1E3A8A))),
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
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
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
              return Card(
                color: isResolved ? Colors.green[50] : Colors.red[50],
                child: ListTile(
                  leading: Icon(
                    isResolved ? Icons.check_circle : Icons.warning,
                    color: isResolved ? Colors.green : Colors.red,
                  ),
                  title: Text('Category: ${incident['incidentType']}'),
                  subtitle: Text(incident['description']),
                  trailing: Text(
                    incident['resolutionStatus'],
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: isResolved ? Colors.green : Colors.red,
                    ),
                  ),
                ),
              );
            }),
        ],
      ),
    );
  }
}

// -------------------------------------------------------------
// ---------------- ADMIN & MANAGER MOBILE DASHBOARD -----------
// -------------------------------------------------------------

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

    final tabs = [
      const AdminHomeTab(),
      const AdminTeamTab(),
      const AdminLiveActivitiesTab(),
      const AdminIncidentOversightTab(),
      const TelecallerScreen(useDesktopLayout: true),
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text(_currentIndex == 0
            ? 'Manager Command Center'
            : _currentIndex == 1
                ? 'Field Force Directory'
                : _currentIndex == 2
                    ? 'Field Activity Audit'
                    : _currentIndex == 3
                        ? 'Incident Oversight'
                        : 'Telecaller Leads'),
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
            onPressed: () => appProvider.logout('mock-device-fingerprint-123456'),
          ),
        ],
      ),
      body: tabs[_currentIndex],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) {
          setState(() {
            _currentIndex = index;
          });
        },
        type: BottomNavigationBarType.fixed,
        selectedItemColor: const Color(0xFF1E3A8A),
        unselectedItemColor: Colors.grey,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.insights_outlined),
            activeIcon: Icon(Icons.insights),
            label: 'Oversight',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.people_outline),
            activeIcon: Icon(Icons.people),
            label: 'Team',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.assignment_outlined),
            activeIcon: Icon(Icons.assignment),
            label: 'Logs',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.notification_important_outlined),
            activeIcon: Icon(Icons.notification_important),
            label: 'Incidents',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.headset_mic_outlined),
            activeIcon: Icon(Icons.headset_mic),
            label: 'Telecaller',
          ),
        ],
      ),
    );
  }
}

class AdminHomeTab extends StatelessWidget {
  const AdminHomeTab({super.key});

  @override
  Widget build(BuildContext context) {
    final appProvider = Provider.of<AppProvider>(context);
    final stats = appProvider.adminStats ?? {};

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Organization Profile Header
          Card(
            color: const Color(0xFF1E3A8A),
            child: Padding(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                children: [
                  const Icon(Icons.business, color: Colors.white70, size: 36),
                  const SizedBox(height: 8),
                  Text(
                    stats['org']?['name'] ?? 'Loading Corp...',
                    style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Workspace: ${stats['org']?['email'] ?? "admin@alpha.com"}',
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                  const SizedBox(height: 4),
                  const Chip(
                    label: Text('MANAGEMENT DESK', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                    backgroundColor: Color(0xFFF59E0B),
                    padding: EdgeInsets.zero,
                  )
                ],
              ),
            ),
          ),
          
          const SizedBox(height: 16),
          const Padding(
            padding: EdgeInsets.only(left: 8.0, bottom: 8),
            child: Text('LIVE FIELD KEY PERFORMANCE INDICATORS', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey)),
          ),

          // KPIs Grid
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 1.3,
            children: [
              _buildKpiCard('Active Execs', '${stats['active_executives'] ?? 0}', Icons.directions_walk, Colors.blue),
              _buildKpiCard('Total Distance', '${(stats['distance_covered_km'] ?? 0.0).toStringAsFixed(1)} KM', Icons.map, Colors.purple),
              _buildKpiCard('Visits Done', '${stats['visits_completed'] ?? 0}', Icons.storefront, Colors.green),
              _buildKpiCard('Sales Value', '\$${(stats['sales_value_total'] ?? 0.0).toStringAsFixed(2)}', Icons.payments, Colors.teal),
            ],
          ),

          const SizedBox(height: 16),
          
          // Emergency alerts card
          Card(
            color: (stats['open_incidents_count'] ?? 0) > 0 ? Colors.red[50] : Colors.green[50],
            child: ListTile(
              leading: Icon(
                (stats['open_incidents_count'] ?? 0) > 0 ? Icons.warning_amber_rounded : Icons.check_circle_outline,
                color: (stats['open_incidents_count'] ?? 0) > 0 ? Colors.red : Colors.green,
                size: 32,
              ),
              title: Text(
                (stats['open_incidents_count'] ?? 0) > 0 
                    ? 'Active Incidents Pending' 
                    : 'All Systems Nominal',
                style: TextStyle(fontWeight: FontWeight.bold, color: (stats['open_incidents_count'] ?? 0) > 0 ? Colors.red[900] : Colors.green[900]),
              ),
              subtitle: Text(
                (stats['open_incidents_count'] ?? 0) > 0 
                    ? 'An executive reported a breakdown or exception. Open the Incidents tab to resolve.'
                    : 'Field sales force is moving smoothly. No emergency exceptions reported.',
                style: const TextStyle(fontSize: 11),
              ),
            ),
          ),

          const SizedBox(height: 16),
          Card(
            child: ListTile(
              leading: const CircleAvatar(
                backgroundColor: Color(0xFF1E3A8A),
                foregroundColor: Colors.white,
                child: Icon(Icons.timer),
              ),
              title: const Text('Automatic Visit Policy', style: TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Text('Minimum outlet stay: ${appProvider.minimumVisitDurationMinutes} minutes'),
              trailing: const Icon(Icons.edit),
              onTap: () => _showVisitDurationSettings(context, appProvider),
            ),
          ),

          Card(
            child: ListTile(
              leading: const CircleAvatar(
                backgroundColor: Colors.teal,
                foregroundColor: Colors.white,
                child: Icon(Icons.table_chart),
              ),
              title: const Text('Excel Export', style: TextStyle(fontWeight: FontWeight.bold)),
              subtitle: const Text('Export outlet visits, remarks, products, GPS, and sales as CSV.'),
              trailing: const Icon(Icons.download),
              onTap: () async {
                final path = await appProvider.exportVisitsCsv();
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Visit report exported: $path'), backgroundColor: Colors.green),
                  );
                }
              },
            ),
          ),
        ],
      ),
    );
  }

  void _showVisitDurationSettings(BuildContext context, AppProvider provider) {
    var selectedMinutes = provider.minimumVisitDurationMinutes;
    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Minimum Visit Duration'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Set how long an executive must remain near an outlet before it can be auto-registered.'),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<int>(
                    value: selectedMinutes,
                    decoration: const InputDecoration(
                      labelText: 'Duration',
                      border: OutlineInputBorder(),
                    ),
                    items: [1, 2, 3, 4, 5, 10, 15, 30].map((minutes) {
                      return DropdownMenuItem(value: minutes, child: Text('$minutes minutes'));
                    }).toList(),
                    onChanged: (value) {
                      if (value != null) {
                        setDialogState(() => selectedMinutes = value);
                      }
                    },
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
                    await provider.setMinimumVisitDurationMinutes(selectedMinutes);
                    if (context.mounted) Navigator.pop(context);
                  },
                  child: const Text('SAVE'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildKpiCard(String label, String value, IconData icon, Color color) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Icon(icon, color: color, size: 24),
                Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey, fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 8),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                value,
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class AdminTeamTab extends StatefulWidget {
  const AdminTeamTab({super.key});

  @override
  State<AdminTeamTab> createState() => _AdminTeamTabState();
}

class _AdminTeamTabState extends State<AdminTeamTab> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passController = TextEditingController();

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passController.dispose();
    super.dispose();
  }

  void _showAddUserSheet(BuildContext context, AppProvider provider) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
            left: 20,
            right: 20,
            top: 24,
          ),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('Create New Executive (POST /users)', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF1E3A8A)), textAlign: TextAlign.center),
                const SizedBox(height: 16),
                
                TextFormField(
                  controller: _nameController,
                  decoration: const InputDecoration(labelText: 'Full Name', border: OutlineInputBorder(), prefixIcon: Icon(Icons.person)),
                  validator: (v) => v == null || v.trim().isEmpty ? 'Please enter a name' : null,
                ),
                const SizedBox(height: 12),
                
                TextFormField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(labelText: 'Email Address', border: OutlineInputBorder(), prefixIcon: Icon(Icons.email)),
                  validator: (v) => v == null || !v.contains('@') ? 'Please enter a valid email' : null,
                ),
                const SizedBox(height: 12),
                
                TextFormField(
                  controller: _passController,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: 'Initial Password', border: OutlineInputBorder(), prefixIcon: Icon(Icons.lock)),
                  validator: (v) => v == null || v.length < 6 ? 'Password must be at least 6 characters' : null,
                ),
                const SizedBox(height: 20),
                
                ElevatedButton(
                  onPressed: () async {
                    if (_formKey.currentState!.validate()) {
                      Navigator.pop(context);
                      final success = await provider.createExecutive(
                        _nameController.text.trim(),
                        _emailController.text.trim(),
                        _passController.text,
                      );
                      
                      if (success && context.mounted) {
                        _nameController.clear();
                        _emailController.clear();
                        _passController.clear();
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Executive account created successfully! Added to directory.'), backgroundColor: Colors.green),
                        );
                      }
                    }
                  },
                  child: const Text('CREATE FIELD ACCOUNT'),
                ),
                const SizedBox(height: 30),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final appProvider = Provider.of<AppProvider>(context);

    return Scaffold(
      body: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: appProvider.adminUsersList.length,
        itemBuilder: (context, idx) {
          final user = appProvider.adminUsersList[idx];
          final isActive = user['status'] == 'active';
          final checkInLabel = _formatTeamAttendanceTime(_firstAvailableValue(user, ['check_in_at', 'checkInAt', 'login_time', 'logged_in_at', 'last_login']));
          final checkOutLabel = _formatTeamAttendanceTime(_firstAvailableValue(user, ['check_out_at', 'checkOutAt', 'logout_time', 'logged_out_at', 'last_logout']));

          return Card(
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor: const Color(0xFF1E3A8A),
                foregroundColor: Colors.white,
                child: Text(user['name'].toString().substring(0, 1).toUpperCase()),
              ),
              title: Text(user['name'], style: const TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${user['designation'] ?? "Field Agent"}\n${user['email']}'),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      _buildTeamAttendanceChip('Check-in', checkInLabel ?? (isActive ? 'Online now' : 'Not checked in'), Colors.green),
                      _buildTeamAttendanceChip('Check-out', checkOutLabel ?? (isActive ? 'Pending logout' : 'Not logged out'), Colors.orange),
                    ],
                  ),
                ],
              ),
              isThreeLine: true,
              trailing: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Chip(
                    label: Text(isActive ? 'ONLINE' : 'OFFLINE', style: const TextStyle(fontSize: 9, color: Colors.white, fontWeight: FontWeight.bold)),
                    backgroundColor: isActive ? Colors.green : Colors.grey,
                    padding: EdgeInsets.zero,
                  ),
                ],
              ),
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showAddUserSheet(context, appProvider),
        backgroundColor: const Color(0xFF1E3A8A),
        foregroundColor: Colors.white,
        tooltip: 'Add Field Executive',
        child: const Icon(Icons.person_add),
      ),
    );
  }

  Widget _buildTeamAttendanceChip(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Text(
        '$label: $value',
        style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.bold),
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
      padding: const EdgeInsets.all(16.0),
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
            ...incidents.map((inc) {
              final isResolved = inc['resolutionStatus'] == 'RESOLVED';
              return Card(
                color: isResolved ? Colors.green[50] : Colors.red[50],
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Category: ${inc['incidentType']}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                          Chip(
                            label: Text(inc['resolutionStatus'], style: const TextStyle(fontSize: 10, color: Colors.white, fontWeight: FontWeight.bold)),
                            backgroundColor: isResolved ? Colors.green : Colors.red,
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(inc['description'], style: const TextStyle(fontSize: 14)),
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
                            style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
                            onPressed: () {
                              // Direct action
                              inc['resolutionStatus'] = 'RESOLVED';
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Incident resolved! Executive notified.'), backgroundColor: Colors.green),
                              );
                              // Force local state update
                              appProvider.fetchUserIncidents();
                              appProvider.fetchAdminStats();
                            },
                          ),
                        ),
                    ],
                  ),
                ),
              );
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
            labelColor: Color(0xFF1E3A8A),
            indicatorColor: Color(0xFF1E3A8A),
            tabs: [
              Tab(icon: Icon(Icons.storefront), text: 'Visits & Orders'),
              Tab(icon: Icon(Icons.location_on), text: 'GPS Location Pings'),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                // 1. VISITS AND ORDERS AUDIT
                _buildVisitsSubTab(context, visits),

                // 2. GPS PIN TRACK AUDIT
                _buildGpsSubTab(gpsPings),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVisitsSubTab(BuildContext context, List<dynamic> visits) {
    if (visits.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.store_outlined, size: 64, color: Colors.grey),
              SizedBox(height: 12),
              Text('No live visits logged yet.', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
              Text('Log in as an executive to perform check-ins, then refresh.', textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: Colors.grey)),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: visits.length,
      itemBuilder: (context, idx) {
        final visit = visits[idx];
        final checkedOut = visit['checkOutTime'] != null;

        return Card(
          elevation: 2,
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(visit['outletName'], style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF1E3A8A))),
                    ),
                    Chip(
                      label: Text(checkedOut ? 'COMPLETED' : 'IN VISIT', style: const TextStyle(fontSize: 9, color: Colors.white, fontWeight: FontWeight.bold)),
                      backgroundColor: checkedOut ? Colors.green : Colors.orange,
                      padding: EdgeInsets.zero,
                    ),
                  ],
                ),
                Text(visit['outletAddress'], style: const TextStyle(fontSize: 12, color: Colors.grey)),
                const Divider(height: 20),
                
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('CHECK-IN AT', style: TextStyle(fontSize: 10, color: Colors.grey, fontWeight: FontWeight.bold)),
                        Text(_formatTime(visit['checkInTime']), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                      ],
                    ),
                    if (checkedOut)
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('CHECK-OUT AT', style: TextStyle(fontSize: 10, color: Colors.grey, fontWeight: FontWeight.bold)),
                          Text(_formatTime(visit['checkOutTime']), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                        ],
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('ORDER GENERATED', style: TextStyle(fontSize: 10, color: Colors.grey, fontWeight: FontWeight.bold)),
                        Text('\$${(visit['salesValue'] ?? 0.0).toStringAsFixed(2)}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.teal)),
                      ],
                    ),
                    if (visit['managerOverride'] == true)
                      const Chip(
                        avatar: Icon(Icons.warning, size: 14, color: Colors.white),
                        label: Text('GEOFENCE OVERRIDE', style: TextStyle(fontSize: 8, color: Colors.white, fontWeight: FontWeight.bold)),
                        backgroundColor: Colors.redAccent,
                      )
                  ],
                ),
                const SizedBox(height: 12),
                
                Text('Client Remarks: "${visit['remarks']}"', style: const TextStyle(fontSize: 12, fontStyle: FontStyle.italic)),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.blueGrey[50],
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.my_location, size: 18, color: Color(0xFF1E3A8A)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Location: ${visit['address'] ?? 'Address not resolved'}',
                              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                            ),
                            Text(
                              'GPS: ${_formatCoordinate(visit['gpsLat'])}, ${_formatCoordinate(visit['gpsLng'])}',
                              style: const TextStyle(fontSize: 11, color: Colors.grey),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                
                // Show Selfie preview if recorded!
                if (visit['selfieUrl'] != null && visit['selfieUrl'].toString().isNotEmpty) ...[
                  const SizedBox(height: 12),
                  const Text('Identity Verification selfie:', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey)),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: visit['selfieUrl'].toString().startsWith('http')
                        ? Image.network(visit['selfieUrl'], height: 100, width: 100, fit: BoxFit.cover)
                        : Image.file(File(visit['selfieUrl']), height: 100, width: 100, fit: BoxFit.cover),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildGpsSubTab(List<dynamic> gpsPings) {
    if (gpsPings.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.location_off_outlined, size: 64, color: Colors.grey),
              SizedBox(height: 12),
              Text('No live GPS pings received yet.', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
              Text('Continuous background movement logs are saved here.', textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: Colors.grey)),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: gpsPings.length,
      itemBuilder: (context, idx) {
        final ping = gpsPings[idx];
        final lat = _formatCoordinate(ping['latitude']);
        final lng = _formatCoordinate(ping['longitude']);
        return Card(
          child: ListTile(
            leading: const CircleAvatar(
              backgroundColor: Colors.blueAccent,
              foregroundColor: Colors.white,
              child: Icon(Icons.gps_fixed, size: 20),
            ),
            title: Text(ping['address'] ?? 'Location name not resolved'),
            subtitle: Text('GPS: $lat, $lng\nRecorded on start point: ${ping['startPoint'] ?? "HOME"}'),
            isThreeLine: true,
            trailing: Text(
              _formatTime(ping['timestamp']),
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey),
            ),
          ),
        );
      },
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
}
