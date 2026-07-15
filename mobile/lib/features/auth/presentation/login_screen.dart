import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/design/tokens.dart';
import '../../../core/design/widgets.dart';
import '../../../core/network/app_provider.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _passwordFocus = FocusNode();
  String? _error;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final email = _emailController.text.trim();
    if (email.isEmpty || _passwordController.text.isEmpty) {
      setState(() => _error = 'Enter your email and password to continue.');
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() => _error = null);

    final provider = Provider.of<AppProvider>(context, listen: false);
    const deviceId = 'mock-device-fingerprint-123456';

    final success = await provider.login(
      email,
      _passwordController.text,
      deviceId,
    );

    if (!mounted) return;
    if (!success) {
      setState(() {
        _error = provider.loginError ?? 'Login failed. Please check your credentials.';
      });
    }
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
                          'Sign in to manage your field force and sales routes.',
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
                          textInputAction: TextInputAction.done,
                          onSubmitted: (_) => _submit(),
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
                        const SizedBox(height: BestieTokens.s4),
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
