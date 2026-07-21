import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/design/tokens.dart';
import '../../../core/design/widgets.dart';
import '../../../core/network/app_provider.dart';
import '../../../core/utils/device_id.dart';
import '../../../core/utils/device_location.dart';
import 'blink_selfie_capture_screen.dart';
import 'register_organisation_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _orgSlugController = TextEditingController();
  final _passwordFocus = FocusNode();
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final provider = Provider.of<AppProvider>(context, listen: false);
      final locked = await provider.consumeSubscriptionLockMessage();
      if (!mounted) return;
      if (locked != null) {
        setState(() => _error = locked);
      } else if (provider.loginError != null &&
          provider.loginError!.toLowerCase().contains('payment')) {
        setState(() => _error = provider.loginError);
      }
    });
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _orgSlugController.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  Future<String> _selfieToDataUrl(File file) async {
    final bytes = await file.readAsBytes();
    return 'data:image/jpeg;base64,${base64Encode(bytes)}';
  }

  Future<void> _promptAndRequestLocation() async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Location access'),
        content: const Text(
          'Field executives need GPS for attendance and live tracking in the admin Logs tab. '
          'Tap Continue, then Allow on the system permission prompt.',
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Continue'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    final access = await DeviceLocation.ensureAccess();
    if (!mounted) return;
    if (access == LocationAccessResult.serviceDisabled) {
      setState(() => _error = 'Turn on Location / GPS in phone settings for field tracking.');
      await DeviceLocation.openSettings(locationServices: true);
    } else if (access == LocationAccessResult.deniedForever) {
      setState(() => _error =
          'Location is blocked. Enable it in App Settings → Permissions → Location.');
    }
  }

  /// Production API requires login_selfie_url for executives — once per day at Sign in.
  Future<File?> _captureBlinkSelfieForServer() async {
    if (!mounted) return null;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Daily login selfie'),
        content: const Text(
          'Field executives must capture a blink selfie once per day at sign-in. '
          'Blink your eyes to capture — you will not be asked again after login today.',
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Continue'),
          ),
        ],
      ),
    );
    if (!mounted) return null;
    return BlinkSelfieCaptureScreen.open(
      context,
      title: 'Sign-in selfie — blink to capture',
    );
  }

  Future<void> _submit() async {
    final email = _emailController.text.trim();
    if (email.isEmpty || _passwordController.text.isEmpty) {
      setState(() => _error = 'Enter your email and password to continue.');
      return;
    }
    if (email.contains('@') && !AppProvider.isValidLoginEmail(email)) {
      setState(() => _error = 'Invalid email address. Check for typos (e.g. .com.com).');
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() => _error = null);

    final provider = Provider.of<AppProvider>(context, listen: false);
    final deviceId = await DeviceId.get();
    final orgSlug =
        _orgSlugController.text.trim().isEmpty ? null : _orgSlugController.text.trim();

    // Prefer today's cached login selfie so the camera is not opened twice the same day.
    final cachedSelfie = provider.todaysLoginSelfieUrl;
    var success = await provider.login(
      email,
      _passwordController.text,
      deviceId,
      orgSlug: orgSlug,
      loginSelfieUrl: cachedSelfie,
    );

    if (!mounted) return;
    if (success) {
      // Backend already accepted login — publish daily activity to admin Logs.
      try {
        await provider.finalizeLoginSelfieForToday(selfieDataUrl: cachedSelfie);
      } catch (_) {
        try {
          await provider.markLoginSelfieSatisfiedByServer();
        } catch (_) {}
      }
      return;
    }

    var err = provider.loginError ?? 'Login failed. Please check your credentials.';

    // Server requires selfie for executives — capture once today (backend gate).
    if (err == 'SELFIE_REQUIRED' || err.toLowerCase().contains('selfie')) {
      // Reuse today's cached selfie if we have one (avoids opening camera again).
      String? selfieUrl = cachedSelfie;
      File? photo;
      if (selfieUrl == null || selfieUrl.isEmpty) {
        photo = await _captureBlinkSelfieForServer();
        if (!mounted) return;
        if (photo == null) {
          setState(() => _error =
              'Blink selfie is required to sign in. Please try again and blink your eyes to capture.');
          return;
        }
        selfieUrl = await _selfieToDataUrl(photo);
      }

      success = await provider.login(
        email,
        _passwordController.text,
        deviceId,
        loginSelfieUrl: selfieUrl,
        orgSlug: orgSlug,
      );
      if (!mounted) return;
      if (success) {
        try {
          await provider.finalizeLoginSelfieForToday(
            localSelfiePath: photo?.path,
            selfieDataUrl: selfieUrl,
          );
        } catch (_) {}
        return;
      }
      err = provider.loginError ?? err;
      if (err == 'SELFIE_REQUIRED' || err.toLowerCase().contains('selfie')) {
        setState(() => _error =
            'Selfie was rejected. Try again with a clear face and blink to capture.');
        return;
      }
    }

    if (err.toLowerCase().contains('location')) {
      await _promptAndRequestLocation();
      if (!mounted) return;
      final retry = await provider.login(
        email,
        _passwordController.text,
        deviceId,
        orgSlug: orgSlug,
      );
      if (!mounted) return;
      if (retry) return;
      setState(() => _error = provider.loginError ?? err);
      return;
    }
    setState(() => _error = err);
  }

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<AppProvider>(context);

    return Scaffold(
      body: Stack(
        children: [
          const Positioned.fill(child: BestieLoginBackdrop()),
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(BestieTokens.s5),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 400),
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(
                      BestieTokens.s5,
                      BestieTokens.s6,
                      BestieTokens.s5,
                      BestieTokens.s5,
                    ),
                    decoration: BoxDecoration(
                      color: BestieTokens.cSurface,
                      borderRadius: BorderRadius.circular(BestieTokens.rXl),
                      border: Border.all(color: BestieTokens.cBorderSoft),
                      boxShadow: const [
                        BoxShadow(
                          blurRadius: 40,
                          color: Color(0x33000000),
                          offset: Offset(0, 18),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Center(
                          child: Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: BestieTokens.cBrandSoft,
                              borderRadius: BorderRadius.circular(BestieTokens.rLg),
                            ),
                            child: const BestieLogo(size: 40),
                          ),
                        ),
                        const SizedBox(height: BestieTokens.s4),
                        const Text(
                          'Welcome back',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 26,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.5,
                            color: BestieTokens.cText,
                          ),
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'Sign in to manage your field force and sales routes.\n'
                          'Executives: blink-capture a selfie once per day at Sign in (not again after login).',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: BestieTokens.cTextMuted, height: 1.4),
                        ),
                        const SizedBox(height: BestieTokens.s5),
                        BestieTextField(
                          label: 'Email or Mobile',
                          controller: _emailController,
                          icon: Icons.person_outline,
                          autofocus: true,
                          keyboardType: TextInputType.emailAddress,
                          textInputAction: TextInputAction.next,
                          onSubmitted: (_) => _passwordFocus.requestFocus(),
                        ),
                        const SizedBox(height: BestieTokens.s3),
                        BestieTextField(
                          label: 'Password',
                          controller: _passwordController,
                          focusNode: _passwordFocus,
                          icon: Icons.lock_outline,
                          obscure: true,
                          textInputAction: TextInputAction.next,
                          onSubmitted: (_) => _submit(),
                        ),
                        const SizedBox(height: BestieTokens.s3),
                        BestieTextField(
                          label: 'Organisation slug (optional)',
                          controller: _orgSlugController,
                          icon: Icons.business_outlined,
                          textInputAction: TextInputAction.done,
                        ),
                        if (_error != null) ...[
                          const SizedBox(height: BestieTokens.s3),
                          BestieErrorBanner(message: _error!),
                        ],
                        const SizedBox(height: BestieTokens.s4),
                        BestiePrimaryButton(
                          label: 'Sign in',
                          onPressed: _submit,
                          loading: provider.isLoading,
                        ),
                        const SizedBox(height: BestieTokens.s3),
                        TextButton(
                          onPressed: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(builder: (_) => const RegisterOrganisationScreen()),
                            );
                          },
                          child: const Text('Register organisation'),
                        ),
                        const SizedBox(height: BestieTokens.s2),
                        const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.lock_outline, size: 13, color: BestieTokens.cTextFaint),
                            SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                'Forgot your credentials? Contact your administrator.',
                                textAlign: TextAlign.center,
                                style: TextStyle(fontSize: 12, color: BestieTokens.cTextFaint),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
