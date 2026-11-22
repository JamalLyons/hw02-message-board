import 'package:firebase_auth/firebase_auth.dart';
import 'package:hw02_message_board/models/app_user.dart';
import 'package:hw02_message_board/screens/board_screen.dart';
import 'package:hw02_message_board/services/auth_service.dart';
import 'package:hw02_message_board/services/board_service.dart';
import 'package:material_ui/material_ui.dart';

/// Loads the signed-in profile, then shows the board or a completion form.
class ProfileGate extends StatefulWidget {
  const ProfileGate({
    super.key,
    required this.user,
    required this.auth,
    required this.board,
  });

  final User user;
  final AuthService auth;
  final BoardService board;

  @override
  State<ProfileGate> createState() => _ProfileGateState();
}

class _ProfileGateState extends State<ProfileGate> {
  static const _maxAttempts = 3;
  static const _retryDelay = Duration(milliseconds: 500);

  final _formKey = GlobalKey<FormState>();
  final _firstName = TextEditingController();
  final _lastName = TextEditingController();

  AppUser? _record;
  String? _role;
  String? _errorMessage;
  String? _saveError;
  bool _loading = true;
  bool _saving = false;
  int _loadGeneration = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _firstName.dispose();
    _lastName.dispose();
    super.dispose();
  }

  /// Reads the profile up to three times. Registration writes the document
  /// just after the account exists, so a missing or incomplete record is retried.
  Future<void> _load() async {
    final generation = ++_loadGeneration;
    if (!_loading || _errorMessage != null) {
      setState(() {
        _loading = true;
        _errorMessage = null;
      });
    }

    AppUser? latest;
    Object? lastError;
    for (var attempt = 1; attempt <= _maxAttempts; attempt++) {
      if (attempt > 1) {
        await Future<void>.delayed(_retryDelay);
        if (!mounted || generation != _loadGeneration) return;
      }
      try {
        latest = await widget.board.getUserRecord(widget.user.uid);
        lastError = null;
        if (latest != null && latest.isComplete) break;
      } catch (error) {
        lastError = error;
      }
      if (!mounted || generation != _loadGeneration) return;
    }

    if (!mounted || generation != _loadGeneration) return;
    if (lastError != null && latest == null) {
      setState(() {
        _loading = false;
        _errorMessage = lastError.toString();
      });
      return;
    }
    _fillFrom(latest);
    setState(() {
      _loading = false;
      _errorMessage = null;
      _record = latest;
    });
  }

  void _fillFrom(AppUser? record) {
    if (record == null) return;
    _firstName.text = record.firstName;
    _lastName.text = record.lastName;
    final role = record.role.trim();
    _role = BoardService.roles.contains(role) ? role : null;
  }

  Future<void> _save() async {
    final form = _formKey.currentState;
    if (form == null || !form.validate() || _saving) return;
    final role = _role;
    if (role == null || role.isEmpty) return;

    setState(() {
      _saving = true;
      _saveError = null;
    });
    try {
      await widget.board.saveUserRecord(
        uid: widget.user.uid,
        firstName: _firstName.text.trim(),
        lastName: _lastName.text.trim(),
        role: role,
      );
      if (!mounted) return;
      setState(() => _saving = false);
      await _load();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _saveError = error.toString();
      });
    }
  }

  Future<void> _signOut() async {
    try {
      await widget.auth.signOut();
    } catch (error) {
      if (!mounted) return;
      final message = error.toString();
      setState(() {
        _saveError = message;
        if (_errorMessage != null || _record == null) {
          _errorMessage = message;
          _loading = false;
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('Loading your profile…'),
            ],
          ),
        ),
      );
    }

    final errorMessage = _errorMessage;
    if (errorMessage != null) {
      return Scaffold(
        body: _ErrorBody(
          message: errorMessage,
          onRetry: _load,
          onSignOut: _signOut,
        ),
      );
    }

    final record = _record;
    if (record != null && record.isComplete) {
      return BoardScreen(
        profile: record,
        auth: widget.auth,
        board: widget.board,
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Complete your profile')),
      body: _ProfileForm(
        formKey: _formKey,
        firstName: _firstName,
        lastName: _lastName,
        role: _role,
        saving: _saving,
        saveError: _saveError,
        onRoleChanged: (value) => setState(() => _role = value),
        onSave: _save,
        onSignOut: _signOut,
      ),
    );
  }
}

class _ErrorBody extends StatelessWidget {
  const _ErrorBody({
    required this.message,
    required this.onRetry,
    required this.onSignOut,
  });

  final String message;
  final VoidCallback onRetry;
  final VoidCallback onSignOut;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton(onPressed: onRetry, child: const Text('Retry')),
            TextButton(onPressed: onSignOut, child: const Text('Sign out')),
          ],
        ),
      ),
    );
  }
}

class _ProfileForm extends StatelessWidget {
  const _ProfileForm({
    required this.formKey,
    required this.firstName,
    required this.lastName,
    required this.role,
    required this.saving,
    required this.saveError,
    required this.onRoleChanged,
    required this.onSave,
    required this.onSignOut,
  });

  final GlobalKey<FormState> formKey;
  final TextEditingController firstName;
  final TextEditingController lastName;
  final String? role;
  final bool saving;
  final String? saveError;
  final ValueChanged<String?> onRoleChanged;
  final VoidCallback onSave;
  final VoidCallback onSignOut;

  @override
  Widget build(BuildContext context) {
    return Form(
      key: formKey,
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          TextFormField(
            controller: firstName,
            textInputAction: TextInputAction.next,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(labelText: 'First name'),
            validator: (value) => _required(value, 'Enter your first name.'),
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: lastName,
            textInputAction: TextInputAction.next,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(labelText: 'Last name'),
            validator: (value) => _required(value, 'Enter your last name.'),
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            initialValue: role,
            decoration: const InputDecoration(labelText: 'Role'),
            items: [
              for (final role in BoardService.roles)
                DropdownMenuItem(value: role, child: Text(_roleLabel(role))),
            ],
            onChanged: saving ? null : onRoleChanged,
            validator: (value) => _required(value, 'Select a role.'),
          ),
          if (saveError != null) ...[
            const SizedBox(height: 16),
            Text(
              saveError!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
          const SizedBox(height: 24),
          FilledButton(
            onPressed: saving ? null : onSave,
            child: const Text('Save'),
          ),
          TextButton(onPressed: onSignOut, child: const Text('Sign out')),
        ],
      ),
    );
  }

  static String? _required(String? value, String message) {
    if (value == null || value.trim().isEmpty) return message;
    return null;
  }

  static String _roleLabel(String role) {
    if (role.isEmpty) return role;
    return '${role[0].toUpperCase()}${role.substring(1)}';
  }
}
