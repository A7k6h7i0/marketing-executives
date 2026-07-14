import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'core/network/app_provider.dart';
import 'features/auth/presentation/login_screen.dart';
import 'features/dashboard/presentation/dashboard_screen.dart';
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
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF1E3A8A), // Deep Blue primary
            primary: const Color(0xFF1E3A8A),
            secondary: const Color(0xFFF59E0B), // Amber accent
            surface: const Color(0xFFF3F4F6), // Light gray background
          ),
          appBarTheme: const AppBarTheme(
            backgroundColor: Color(0xFF1E3A8A),
            foregroundColor: Colors.white,
            elevation: 0,
            centerTitle: true,
          ),
          elevatedButtonTheme: ElevatedButtonThemeData(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1E3A8A),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 24),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
        ),
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
        return const TelecallerDashboardScreen();
      }
      if (role == 'SUPER_ADMIN' ||
          role == 'REGIONAL_MANAGER' ||
          role == 'SALES_MANAGER' ||
          role == 'admin' ||
          role == 'manager') {
        return const AdminDashboardScreen();
      }
      return const DashboardScreen();
    } else {
      return const LoginScreen();
    }
  }
}
