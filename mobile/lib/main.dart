import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'core/design/theme.dart';
import 'core/network/app_provider.dart';
import 'features/auth/presentation/login_screen.dart';
import 'features/dashboard/presentation/dashboard_screen.dart';
import 'features/telecaller/presentation/telecaller_onboarding_screen.dart';
import 'features/telecaller/presentation/telecaller_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const FieldForceApp());
}

class FieldForceApp extends StatelessWidget {
  const FieldForceApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => AppProvider(),
      child: MaterialApp(
        title: 'Field Force Management',
        debugShowCheckedModeBanner: false,
        theme: BestieTheme.light(),
        home: const AuthGate(),
      ),
    );
  }
}

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AppProvider>(context);

    if (authProvider.isAuthenticated) {
      final role = authProvider.role ?? '';
      if (role == 'TELECALLER') {
        if (!authProvider.telecallerSetupLoaded) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        if (!authProvider.telecallerSetupComplete) {
          return TelecallerOnboardingScreen(
            onComplete: () {
              authProvider.reloadTelecallerSetup();
            },
          );
        }
        return const TelecallerDashboardScreen();
      }
      if (role == 'SUPER_ADMIN' ||
          role == 'REGIONAL_MANAGER' ||
          role == 'SALES_MANAGER' ||
          role == 'admin' ||
          role == 'manager') {
        return const AdminDashboardScreen();
      }
      if (role == 'executive' || role == 'SALES_EXECUTIVE') {
        return const DashboardScreen();
      }
      return const DashboardScreen();
    } else {
      return const LoginScreen();
    }
  }
}
