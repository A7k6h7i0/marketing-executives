import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/design/tokens.dart';
import '../../../core/network/app_provider.dart';

class ProductsAdminScreen extends StatefulWidget {
  const ProductsAdminScreen({super.key});

  @override
  State<ProductsAdminScreen> createState() => _ProductsAdminScreenState();
}

class _ProductsAdminScreenState extends State<ProductsAdminScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<AppProvider>(context, listen: false).fetchProductAdminLists();
    });
  }

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<AppProvider>(context);
    final canManage = provider.canManageProductCatalog;

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Products'),
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: () => provider.fetchProductAdminLists(),
            ),
          ],
          bottom: TabBar(
            tabs: [
              Tab(text: 'Products (${provider.productCatalog.length})'),
              Tab(text: 'Brands (${provider.productBrandsAdmin.length})'),
              Tab(text: 'Categories (${provider.productCategoriesAdmin.length})'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _ProductsTab(provider: provider, canManage: canManage),
            _NamedItemsTab(
              title: 'Brand',
              items: provider.productBrandsAdmin,
              canManage: canManage,
              onCreate: (name) => provider.createProductBrandAdmin(name),
              onUpdate: (id, name) => provider.updateProductBrandAdmin(id, name),
              onDelete: (id) => provider.deleteProductBrandAdmin(id),
              lastError: () => provider.lastActionError,
            ),
            _NamedItemsTab(
              title: 'Category',
              items: provider.productCategoriesAdmin,
              canManage: canManage,
              onCreate: (name) => provider.createProductCategoryAdmin(name),
              onUpdate: (id, name) => provider.updateProductCategoryAdmin(id, name),
              onDelete: (id) => provider.deleteProductCategoryAdmin(id),
              lastError: () => provider.lastActionError,
            ),
          ],
        ),
      ),
    );
  }
}

InputDecoration _formFieldDecoration({
  required String label,
  required IconData icon,
  String? hint,
  String? suffixText,
}) {
  return InputDecoration(
    labelText: label,
    hintText: hint,
    suffixText: suffixText,
    floatingLabelBehavior: FloatingLabelBehavior.auto,
    labelStyle: const TextStyle(color: BestieTokens.cBrand, fontWeight: FontWeight.w600),
    floatingLabelStyle: const TextStyle(color: BestieTokens.cBrand, fontWeight: FontWeight.w600),
    prefixIcon: Padding(
      padding: const EdgeInsets.all(10),
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: BestieTokens.cBrandSoft,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, size: 18, color: BestieTokens.cBrand),
      ),
    ),
    prefixIconConstraints: const BoxConstraints(minWidth: 52, minHeight: 44),
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

Widget _modalHeader({
  required IconData icon,
  required String title,
  required String subtitle,
  required VoidCallback onClose,
}) {
  return Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: BestieTokens.cBrandSoft,
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: BestieTokens.cBrand),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: BestieTokens.cText)),
            const SizedBox(height: 2),
            Text(subtitle, style: const TextStyle(fontSize: 12, color: BestieTokens.cTextMuted, height: 1.3)),
          ],
        ),
      ),
      InkWell(
        onTap: onClose,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: BestieTokens.cSurface2,
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.close, size: 18, color: BestieTokens.cTextSoft),
        ),
      ),
    ],
  );
}

Widget _formTip(String text) {
  return Container(
    width: double.infinity,
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: BestieTokens.cSurface2,
      borderRadius: BorderRadius.circular(12),
    ),
    child: Row(
      children: [
        Container(
          width: 28,
          height: 28,
          decoration: const BoxDecoration(
            color: BestieTokens.cBrandSoft,
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.auto_awesome, size: 14, color: BestieTokens.cBrand),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(text, style: const TextStyle(fontSize: 12, color: BestieTokens.cTextSoft, height: 1.35)),
        ),
      ],
    ),
  );
}

Widget _modalActions({
  required VoidCallback onCancel,
  required VoidCallback onSave,
  String saveLabel = 'Save',
}) {
  return Row(
    children: [
      Expanded(
        child: OutlinedButton(
          onPressed: onCancel,
          style: OutlinedButton.styleFrom(
            foregroundColor: BestieTokens.cBrand,
            side: const BorderSide(color: BestieTokens.cBorder),
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          child: const Text('Cancel', style: TextStyle(fontWeight: FontWeight.w600)),
        ),
      ),
      const SizedBox(width: 10),
      Expanded(
        child: ElevatedButton.icon(
          onPressed: onSave,
          icon: const Icon(Icons.save_outlined, size: 18),
          label: Text(saveLabel),
          style: ElevatedButton.styleFrom(
            backgroundColor: BestieTokens.cBrand,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
      ),
    ],
  );
}

class _ProductsTab extends StatelessWidget {
  const _ProductsTab({required this.provider, required this.canManage});

  final AppProvider provider;
  final bool canManage;

  Future<void> _openEditor(BuildContext context, {Map? existing}) async {
    final nameCtrl = TextEditingController(text: existing?['name']?.toString() ?? '');
    final skuCtrl = TextEditingController(text: existing?['sku']?.toString() ?? '');
    final mrpCtrl = TextEditingController(
      text: existing?['mrp']?.toString() ?? existing?['unitPrice']?.toString() ?? '',
    );
    final ptrCtrl = TextEditingController(text: existing?['ptr']?.toString() ?? '');
    String? categoryId = existing?['category_id']?.toString();
    String? brandId = existing?['brand_id']?.toString();

    final categories = provider.productCategoriesAdmin;
    final brands = provider.productBrandsAdmin;
    if (categoryId != null && !categories.any((c) => c['id']?.toString() == categoryId)) {
      categoryId = null;
    }
    if (brandId != null && !brands.any((b) => b['id']?.toString() == brandId)) {
      brandId = null;
    }

    final isEdit = existing != null;
    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => Dialog(
          insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(ctx).size.height * 0.88,
              maxWidth: 420,
            ),
            child: Padding(
              padding: EdgeInsets.fromLTRB(20, 20, 20, 16 + MediaQuery.of(ctx).viewInsets.bottom * 0.2),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _modalHeader(
                    icon: isEdit ? Icons.edit_outlined : Icons.inventory_2_outlined,
                    title: isEdit ? 'Edit Product' : 'Add Product',
                    subtitle: isEdit ? 'Update the product details' : 'Enter product details to add a new item',
                    onClose: () => Navigator.pop(ctx, false),
                  ),
                  const SizedBox(height: 18),
                  Flexible(
                    child: SingleChildScrollView(
                      child: Column(
                        children: [
                          TextField(
                            controller: nameCtrl,
                            decoration: _formFieldDecoration(
                              label: 'Name',
                              icon: Icons.sell_outlined,
                              hint: 'Enter product name',
                            ),
                          ),
                          const SizedBox(height: 14),
                          TextField(
                            controller: skuCtrl,
                            decoration: _formFieldDecoration(
                              label: 'SKU',
                              icon: Icons.qr_code_2_outlined,
                              hint: 'Enter SKU',
                            ),
                          ),
                          const SizedBox(height: 14),
                          TextField(
                            controller: mrpCtrl,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            decoration: _formFieldDecoration(
                              label: 'MRP',
                              icon: Icons.currency_rupee,
                              hint: '0.00',
                              suffixText: '₹',
                            ),
                          ),
                          const SizedBox(height: 14),
                          TextField(
                            controller: ptrCtrl,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            decoration: _formFieldDecoration(
                              label: 'PTR (Trade Rate)',
                              icon: Icons.swap_horiz,
                              hint: '0.00',
                              suffixText: '₹',
                            ),
                          ),
                          const SizedBox(height: 14),
                          DropdownButtonFormField<String?>(
                            initialValue: categoryId,
                            decoration: _formFieldDecoration(
                              label: 'Category',
                              icon: Icons.folder_outlined,
                            ),
                            items: [
                              const DropdownMenuItem<String?>(value: null, child: Text('None')),
                              ...categories.map(
                                (c) => DropdownMenuItem<String?>(
                                  value: c['id']?.toString(),
                                  child: Text(c['name']?.toString() ?? 'Category'),
                                ),
                              ),
                            ],
                            onChanged: (v) => setLocal(() => categoryId = v),
                          ),
                          const SizedBox(height: 14),
                          DropdownButtonFormField<String?>(
                            initialValue: brandId,
                            decoration: _formFieldDecoration(
                              label: 'Brand',
                              icon: Icons.local_offer_outlined,
                            ),
                            items: [
                              const DropdownMenuItem<String?>(value: null, child: Text('None')),
                              ...brands.map(
                                (b) => DropdownMenuItem<String?>(
                                  value: b['id']?.toString(),
                                  child: Text(b['name']?.toString() ?? 'Brand'),
                                ),
                              ),
                            ],
                            onChanged: (v) => setLocal(() => brandId = v),
                          ),
                          const SizedBox(height: 14),
                          _formTip('Tip: Keep SKU unique and use INR values for MRP / PTR.'),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  _modalActions(
                    onCancel: () => Navigator.pop(ctx, false),
                    onSave: () => Navigator.pop(ctx, true),
                    saveLabel: isEdit ? 'Save Changes' : 'Save',
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    if (saved != true) return;
    final name = nameCtrl.text.trim();
    final sku = skuCtrl.text.trim();
    final mrp = double.tryParse(mrpCtrl.text.trim()) ?? 0;
    final ptr = double.tryParse(ptrCtrl.text.trim()) ?? 0;
    if (name.isEmpty || sku.isEmpty) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Name and SKU are required.'), backgroundColor: BestieTokens.cText),
        );
      }
      return;
    }

    final ok = existing == null
        ? await provider.createProductAdmin(
            name: name,
            sku: sku,
            mrp: mrp,
            ptr: ptr,
            categoryId: categoryId,
            brandId: brandId,
          )
        : await provider.updateProductAdmin(existing['id'].toString(), {
            'name': name,
            'sku': sku,
            'mrp': mrp,
            'ptr': ptr,
            if (categoryId != null) 'category_id': categoryId,
            if (brandId != null) 'brand_id': brandId,
          });

    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(ok ? 'Product saved.' : (provider.lastActionError ?? 'Save failed.')),
        backgroundColor: ok ? BestieTokens.cBrand : BestieTokens.cText,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final products = provider.productCatalog;
    final catById = {
      for (final c in provider.productCategoriesAdmin) c['id']?.toString() ?? '': c['name']?.toString() ?? '',
    };
    final brandById = {
      for (final b in provider.productBrandsAdmin) b['id']?.toString() ?? '': b['name']?.toString() ?? '',
    };

    return Scaffold(
      body: products.isEmpty
          ? Center(
              child: Text(
                canManage ? 'No products yet. Tap + to add one.' : 'No products in the catalog yet.',
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: products.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final p = products[index];
                final cat = catById[p['category_id']?.toString()] ?? '';
                final brand = brandById[p['brand_id']?.toString()] ?? '';
                return Card(
                  child: ListTile(
                    title: Text(p['name']?.toString() ?? 'Product', style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Text(
                      [
                        'SKU: ${p['sku'] ?? '-'}',
                        if (brand.isNotEmpty) 'Brand: $brand',
                        if (cat.isNotEmpty) 'Category: $cat',
                        'MRP: ₹${p['mrp'] ?? p['unitPrice'] ?? '-'} · PTR: ₹${p['ptr'] ?? '-'}',
                      ].join('\n'),
                    ),
                    isThreeLine: true,
                    trailing: canManage
                        ? PopupMenuButton<String>(
                            onSelected: (action) async {
                              if (action == 'edit') {
                                await _openEditor(context, existing: p as Map);
                              } else if (action == 'delete') {
                                final confirm = await showDialog<bool>(
                                  context: context,
                                  builder: (ctx) => AlertDialog(
                                    title: const Text('Delete product?'),
                                    content: Text('Remove ${p['name']}?'),
                                    actions: [
                                      TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                                      ElevatedButton(
                                        style: ElevatedButton.styleFrom(backgroundColor: BestieTokens.cText, foregroundColor: Colors.white),
                                        onPressed: () => Navigator.pop(ctx, true),
                                        child: const Text('Delete'),
                                      ),
                                    ],
                                  ),
                                );
                                if (confirm != true) return;
                                final ok = await provider.deleteProductAdmin(p['id'].toString());
                                if (!context.mounted) return;
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(ok ? 'Product deleted.' : (provider.lastActionError ?? 'Delete failed.')),
                                    backgroundColor: ok ? BestieTokens.cBrand : BestieTokens.cText,
                                  ),
                                );
                              }
                            },
                            itemBuilder: (_) => const [
                              PopupMenuItem(value: 'edit', child: Text('Edit')),
                              PopupMenuItem(value: 'delete', child: Text('Delete')),
                            ],
                          )
                        : null,
                  ),
                );
              },
            ),
      floatingActionButton: canManage
          ? FloatingActionButton(
              onPressed: () => _openEditor(context),
              backgroundColor: BestieTokens.cBrand,
              foregroundColor: Colors.white,
              child: const Icon(Icons.add),
            )
          : null,
    );
  }
}

class _NamedItemsTab extends StatelessWidget {
  const _NamedItemsTab({
    required this.title,
    required this.items,
    required this.canManage,
    required this.onCreate,
    required this.onUpdate,
    required this.onDelete,
    required this.lastError,
  });

  final String title;
  final List<Map<String, dynamic>> items;
  final bool canManage;
  final Future<bool> Function(String name) onCreate;
  final Future<bool> Function(String id, String name) onUpdate;
  final Future<bool> Function(String id) onDelete;
  final String? Function() lastError;

  Future<void> _promptName(BuildContext context, {String? initial, String? id}) async {
    final ctrl = TextEditingController(text: initial ?? '');
    final isEdit = id != null;
    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: Padding(
          padding: EdgeInsets.fromLTRB(20, 20, 20, 16 + MediaQuery.of(ctx).viewInsets.bottom * 0.15),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _modalHeader(
                icon: title == 'Brand' ? Icons.local_offer_outlined : Icons.category_outlined,
                title: isEdit ? 'Edit $title' : 'Add $title',
                subtitle: isEdit
                    ? 'Update the ${title.toLowerCase()} details'
                    : 'Enter ${title.toLowerCase()} details to add a new ${title.toLowerCase()}',
                onClose: () => Navigator.pop(ctx, false),
              ),
              const SizedBox(height: 18),
              TextField(
                controller: ctrl,
                autofocus: true,
                decoration: _formFieldDecoration(
                  label: '$title Name',
                  icon: Icons.apartment_outlined,
                  hint: 'Enter ${title.toLowerCase()} name',
                ),
              ),
              const SizedBox(height: 14),
              _formTip('Tip: Use a unique and recognizable name for the ${title.toLowerCase()}.'),
              const SizedBox(height: 18),
              _modalActions(
                onCancel: () => Navigator.pop(ctx, false),
                onSave: () => Navigator.pop(ctx, true),
              ),
            ],
          ),
        ),
      ),
    );
    if (saved != true) return;
    final name = ctrl.text.trim();
    if (name.isEmpty) return;
    final ok = id == null ? await onCreate(name) : await onUpdate(id, name);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(ok ? '$title saved.' : (lastError() ?? 'Save failed.')),
        backgroundColor: ok ? BestieTokens.cBrand : BestieTokens.cText,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: items.isEmpty
          ? Center(
              child: Text(
                canManage
                    ? 'No ${title.toLowerCase()}s yet. Tap + to add one.'
                    : 'No ${title.toLowerCase()}s in the catalog yet.',
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: items.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final item = items[index];
                return Card(
                  child: ListTile(
                    title: Text(item['name']?.toString() ?? title, style: const TextStyle(fontWeight: FontWeight.bold)),
                    trailing: canManage
                        ? PopupMenuButton<String>(
                            onSelected: (action) async {
                              if (action == 'edit') {
                                await _promptName(context, initial: item['name']?.toString(), id: item['id']?.toString());
                              } else if (action == 'delete') {
                                final confirm = await showDialog<bool>(
                                  context: context,
                                  builder: (ctx) => AlertDialog(
                                    title: Text('Delete $title?'),
                                    content: Text('Remove ${item['name']}?'),
                                    actions: [
                                      TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                                      ElevatedButton(
                                        style: ElevatedButton.styleFrom(backgroundColor: BestieTokens.cText, foregroundColor: Colors.white),
                                        onPressed: () => Navigator.pop(ctx, true),
                                        child: const Text('Delete'),
                                      ),
                                    ],
                                  ),
                                );
                                if (confirm != true) return;
                                final ok = await onDelete(item['id'].toString());
                                if (!context.mounted) return;
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(ok ? '$title deleted.' : (lastError() ?? 'Delete failed.')),
                                    backgroundColor: ok ? BestieTokens.cBrand : BestieTokens.cText,
                                  ),
                                );
                              }
                            },
                            itemBuilder: (_) => const [
                              PopupMenuItem(value: 'edit', child: Text('Edit')),
                              PopupMenuItem(value: 'delete', child: Text('Delete')),
                            ],
                          )
                        : null,
                  ),
                );
              },
            ),
      floatingActionButton: canManage
          ? FloatingActionButton(
              heroTag: 'fab-$title',
              onPressed: () => _promptName(context),
              backgroundColor: BestieTokens.cBrand,
              foregroundColor: Colors.white,
              child: const Icon(Icons.add),
            )
          : null,
    );
  }
}
