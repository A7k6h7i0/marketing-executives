import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/design/tokens.dart';
import '../../../core/design/widgets.dart';
import '../../../core/network/app_provider.dart';

class RegisterOrganisationScreen extends StatefulWidget {
  const RegisterOrganisationScreen({super.key});

  @override
  State<RegisterOrganisationScreen> createState() => _RegisterOrganisationScreenState();
}

class _RegisterOrganisationScreenState extends State<RegisterOrganisationScreen> {
  final _formKey = GlobalKey<FormState>();
  final _orgName = TextEditingController();
  final _orgSlug = TextEditingController();
  final _orgEmail = TextEditingController();
  final _orgPhone = TextEditingController();
  final _orgAddress = TextEditingController();
  final _ownerName = TextEditingController();
  final _ownerEmail = TextEditingController();
  final _ownerPhone = TextEditingController();
  final _ownerPassword = TextEditingController();
  final _scrollController = ScrollController();
  bool _submitting = false;
  bool _submitted = false;
  bool _slugManual = false;
  String? _message;
  String? _error;

  @override
  void dispose() {
    _orgName.dispose();
    _orgSlug.dispose();
    _orgEmail.dispose();
    _orgPhone.dispose();
    _orgAddress.dispose();
    _ownerName.dispose();
    _ownerEmail.dispose();
    _ownerPhone.dispose();
    _ownerPassword.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  String _slugify(String input) {
    return input
        .toLowerCase()
        .trim()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
  }

  InputDecoration _field(String label, {String? helper, String? hint}) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      helperText: helper,
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: BestieTokens.cBorder),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: BestieTokens.cBrand, width: 1.5),
      ),
    );
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _submitting = true;
      _error = null;
    });

    final provider = Provider.of<AppProvider>(context, listen: false);
    final error = await provider.registerOrganisation(
      orgName: _orgName.text,
      orgSlug: _orgSlug.text.isEmpty ? _slugify(_orgName.text) : _orgSlug.text,
      ownerName: _ownerName.text,
      ownerEmail: _ownerEmail.text,
      ownerPassword: _ownerPassword.text,
      orgEmail: _orgEmail.text,
      orgPhone: _orgPhone.text,
      orgAddress: _orgAddress.text,
      ownerPhone: _ownerPhone.text,
    );

    if (!mounted) return;
    setState(() => _submitting = false);

    if (error == null) {
      setState(() {
        _submitted = true;
        _message =
            'Our team is reviewing your organisation details. We will get back to you soon once your account is approved.';
      });
    } else {
      setState(() => _error = error);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_submitted) {
      return Scaffold(
        appBar: AppBar(title: const Text('Request received')),
        body: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Icon(Icons.hourglass_top, size: 56, color: BestieTokens.cBrand),
              const SizedBox(height: 16),
              const Text(
                'Thank you for registering',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              Text(
                _message ??
                    'Our team is reviewing your organisation details. We will get back to you soon once your account is approved.',
                textAlign: TextAlign.center,
                style: const TextStyle(height: 1.45, color: Colors.black87),
              ),
              const SizedBox(height: 12),
              const Text(
                'You will be able to sign in as the organisation admin after approval. Until then, access remains paused for security.',
                textAlign: TextAlign.center,
                style: TextStyle(height: 1.45, color: Colors.black54),
              ),
              const Spacer(),
              ElevatedButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Back to sign in'),
              ),
            ],
          ),
        ),
      );
    }

    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Scaffold(
      resizeToAvoidBottomInset: true,
      appBar: AppBar(title: const Text('Register organisation')),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  controller: _scrollController,
                  keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: EdgeInsets.fromLTRB(20, 16, 20, 20 + bottomInset),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text(
                        'Register your company to use Marketing Executives. Submit organisation and admin details. '
                        'A platform super admin will approve before your team can use the app.',
                        style: TextStyle(height: 1.4, color: BestieTokens.cTextSoft),
                      ),
                      const SizedBox(height: 20),
                      const Text('Organisation', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _orgName,
                        decoration: _field('Organisation name *'),
                        textInputAction: TextInputAction.next,
                        onChanged: (v) {
                          if (!_slugManual) {
                            setState(() => _orgSlug.text = _slugify(v));
                          }
                        },
                        validator: (v) => v == null || v.trim().isEmpty ? 'Required' : null,
                      ),
                      const SizedBox(height: 14),
                      TextFormField(
                        controller: _orgSlug,
                        decoration: _field(
                          'Organisation slug *',
                          hint: 'e.g. acme-sales',
                          helper: 'Used at login to identify your organisation',
                        ),
                        onChanged: (_) => _slugManual = true,
                        validator: (v) {
                          if (v == null || v.trim().isEmpty) return 'Required';
                          if (!RegExp(r'^[a-z0-9-]{2,60}$').hasMatch(v.trim())) {
                            return 'Use lowercase letters, numbers, hyphens only';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 14),
                      TextFormField(
                        controller: _orgEmail,
                        decoration: _field('Organisation email'),
                        keyboardType: TextInputType.emailAddress,
                      ),
                      const SizedBox(height: 14),
                      TextFormField(
                        controller: _orgPhone,
                        decoration: _field('Organisation phone'),
                        keyboardType: TextInputType.phone,
                      ),
                      const SizedBox(height: 14),
                      TextFormField(
                        controller: _orgAddress,
                        decoration: _field('Address'),
                        maxLines: 3,
                      ),
                      const SizedBox(height: 24),
                      const Text('Organisation admin (owner)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _ownerName,
                        decoration: _field('Admin full name *'),
                        validator: (v) => v == null || v.trim().isEmpty ? 'Required' : null,
                      ),
                      const SizedBox(height: 14),
                      TextFormField(
                        controller: _ownerEmail,
                        decoration: _field('Admin email *'),
                        keyboardType: TextInputType.emailAddress,
                        validator: (v) => v == null || !v.contains('@') ? 'Valid email required' : null,
                      ),
                      const SizedBox(height: 14),
                      TextFormField(
                        controller: _ownerPhone,
                        decoration: _field('Admin phone'),
                        keyboardType: TextInputType.phone,
                      ),
                      const SizedBox(height: 14),
                      TextFormField(
                        controller: _ownerPassword,
                        obscureText: true,
                        decoration: _field('Admin password *'),
                        validator: (v) => v == null || v.length < 6 ? 'At least 6 characters' : null,
                      ),
                      if (_error != null) ...[
                        const SizedBox(height: 14),
                        BestieErrorBanner(message: _error!),
                      ],
                      const SizedBox(height: 12),
                    ],
                  ),
                ),
              ),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(20, 10, 20, 16),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  border: Border(top: BorderSide(color: BestieTokens.cBorderSoft)),
                ),
                child: ElevatedButton(
                  onPressed: _submitting ? null : _submit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: BestieTokens.cBrand,
                    foregroundColor: Colors.white,
                    minimumSize: const Size.fromHeight(48),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: _submitting
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Text('Send request', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
