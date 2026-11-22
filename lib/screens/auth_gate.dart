import 'package:firebase_auth/firebase_auth.dart';
import 'package:hw02_message_board/screens/login_screen.dart';
import 'package:hw02_message_board/screens/profile_gate.dart';
import 'package:hw02_message_board/services/auth_service.dart';
import 'package:hw02_message_board/services/board_service.dart';
import 'package:material_ui/material_ui.dart';

/// Chooses [LoginScreen] or [ProfileGate] from [AuthService.authStateChanges].
class AuthGate extends StatefulWidget {
  const AuthGate({super.key, required this.auth, required this.board});

  final AuthService auth;
  final BoardService board;

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  late Stream<User?> _authState;

  @override
  void initState() {
    super.initState();
    _authState = widget.auth.authStateChanges();
  }

  @override
  void didUpdateWidget(AuthGate oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.auth != widget.auth) {
      _authState = widget.auth.authStateChanges();
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: _authState,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        final user = snapshot.data;
        if (user == null) {
          return LoginScreen(auth: widget.auth, board: widget.board);
        }
        return ProfileGate(
          key: ValueKey(user.uid),
          user: user,
          auth: widget.auth,
          board: widget.board,
        );
      },
    );
  }
}
