import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:hw02_message_board/firebase_options.dart';
import 'package:material_ui/material_ui.dart';

import 'screens/auth_gate.dart';
import 'screens/splash_screen.dart';
import 'services/auth_service.dart';
import 'services/board_service.dart';

/// `--dart-define=USE_EMULATOR=true` points Auth and Firestore at local emulators.
const useEmulator = bool.fromEnvironment('USE_EMULATOR');

/// Emulator host. `10.0.2.2` is the Android emulator's loopback to the host.
const emulatorHost = String.fromEnvironment(
  'EMULATOR_HOST',
  defaultValue: '10.0.2.2',
);

const _seed = Color(0xFF8D4A2B);

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MessageBoardApp());
}

/// Root application: Material 3, system light/dark, splash then auth gate.
class MessageBoardApp extends StatelessWidget {
  const MessageBoardApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Vault Board',
      debugShowCheckedModeBanner: false,
      theme: _theme(Brightness.light),
      darkTheme: _theme(Brightness.dark),
      themeMode: ThemeMode.system,
      home: const BootstrapScreen(),
    );
  }

  ThemeData _theme(Brightness brightness) {
    return ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: _seed,
        brightness: brightness,
      ),
    );
  }
}

/// Initializes Firebase (and optional emulators) before showing [AuthGate].
class BootstrapScreen extends StatefulWidget {
  const BootstrapScreen({super.key});

  @override
  State<BootstrapScreen> createState() => _BootstrapScreenState();
}

class _BootstrapScreenState extends State<BootstrapScreen> {
  static bool _emulatorConfigured = false;

  AuthService? _auth;
  BoardService? _board;
  String? _error;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    if (_error != null) setState(() => _error = null);
    try {
      await Future.wait<void>([
        _initializeFirebase(),
        Future<void>.delayed(const Duration(milliseconds: 1500)),
      ]);
      await _configureEmulators();
      _auth ??= AuthService();
      _board ??= BoardService();
      if (!mounted) return;
      setState(() {});
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString());
    }
  }

  /// Skips a second [Firebase.initializeApp] so Retry can run after a later failure.
  Future<void> _initializeFirebase() {
    if (Firebase.apps.isNotEmpty) return Future<void>.value();
    if (!DefaultFirebaseOptions.isConfigured) {
      return Future<void>.error(
        StateError(
          'Firebase config missing. Build with '
          '--dart-define-from-file=.env.json (see README).',
        ),
      );
    }
    return Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  }

  Future<void> _configureEmulators() async {
    if (!useEmulator || _emulatorConfigured) return;
    await FirebaseAuth.instance.useAuthEmulator(emulatorHost, 9099);
    FirebaseFirestore.instance.useFirestoreEmulator(emulatorHost, 8080);
    _emulatorConfigured = true;
  }

  void _retry() => _init();

  @override
  Widget build(BuildContext context) {
    final auth = _auth;
    final board = _board;
    if (_error == null && auth != null && board != null) {
      return AuthGate(auth: auth, board: board);
    }
    return SplashScreen(error: _error, onRetry: _retry);
  }
}
