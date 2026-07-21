import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'core/design/theme.dart';
import 'core/network/api_client.dart';
import 'core/network/app_provider.dart';
import 'features/auth/presentation/login_screen.dart';
import 'features/dashboard/presentation/dashboard_screen.dart';
import 'features/telecaller/presentation/telecaller_onboarding_screen.dart';
import 'features/telecaller/presentation/telecaller_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Keep UI usable when an unexpected widget error happens on a specific OEM/device.
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    if (kDebugMode) {
      debugPrint(details.toString());
    }
  };
  ErrorWidget.builder = (details) {
    return Material(
      color: Colors.white,
      child: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              'Something went wrong on this screen.\nPlease go back and try again.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade800, fontSize: 15),
            ),
          ),
        ),
      ),
    );
  };

  // Portrait + reverse portrait keeps field layouts stable across phones/foldables.
  await SystemChrome.setPreferredOrientations(const [
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

  runZonedGuarded(
    () => runApp(const FieldForceApp()),
    (error, stack) {
      if (kDebugMode) {
        debugPrint('Uncaught: $error\n$stack');
      }
    },
  );
}

class FieldForceApp extends StatelessWidget {
  const FieldForceApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => AppProvider(),
      child: MaterialApp(
        title: 'Marketing Executives',
        debugShowCheckedModeBanner: false,
        theme: BestieTheme.light(),
        builder: (context, child) {
          // Text scale clamp: accessibility OK, but avoid huge OEM font scales breaking UI.
          final media = MediaQuery.of(context);
          final clamped = media.copyWith(
            textScaler: media.textScaler.clamp(minScaleFactor: 0.85, maxScaleFactor: 1.25),
          );
          return MediaQuery(
            data: clamped,
            child: child ?? const SizedBox.shrink(),
          );
        },
        home: const AuthGate(),
      ),
    );
  }
}

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  @override
  void initState() {
    super.initState();
    ApiClient.subscriptionLockedNotifier.addListener(_onSubscriptionLocked);
  }

  @override
  void dispose() {
    ApiClient.subscriptionLockedNotifier.removeListener(_onSubscriptionLocked);
    super.dispose();
  }

  void _onSubscriptionLocked() {
    if (!ApiClient.subscriptionLockedNotifier.value) return;
    final provider = Provider.of<AppProvider>(context, listen: false);
    // Never lock platform super admin or AddPhoneBook (handled inside forceLogout too).
    provider.forceLogoutForExpiredSubscription();
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AppProvider>(context);

    // Wait until startup session check finishes — never flash a dashboard first.
    if (!authProvider.isSessionReady) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (authProvider.isAuthenticated) {
      final role = authProvider.role ?? '';
      if (role.toUpperCase() == 'TELECALLER') {
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
      final roleLower = role.toLowerCase();
      if (roleLower == 'super_admin' ||
          roleLower == 'admin' ||
          roleLower == 'manager' ||
          roleLower == 'regional_manager' ||
          roleLower == 'sales_manager' ||
          role == 'SUPER_ADMIN' ||
          role == 'REGIONAL_MANAGER' ||
          role == 'SALES_MANAGER') {
        return const AdminDashboardScreen();
      }
      return const DashboardScreen();
    } else {
      return const LoginScreen();
    }
  }
}
