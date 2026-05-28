// lib/presentation/auth/login_screen.dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:local_auth/local_auth.dart';
import 'package:flutter/foundation.dart';
import '../../core/router/app_router.dart';

class LoginScreen extends StatefulWidget {
  final bool showRegister;
  const LoginScreen({super.key, this.showRegister = false});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with TickerProviderStateMixin {
  // ─── Tab State ───────────────────────────────────────────
  late bool _isSignIn;
  bool _isStudent = true;
  bool _isLoading = false;
  String _selectedSex = 'male';

  // ─── Password Visibility ─────────────────────────────────
  bool _passwordVisible = false;
  bool _confirmPasswordVisible = false;
  bool _secretVisible = false;

  // ─── Controllers ─────────────────────────────────────────
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _secretController = TextEditingController();
  final _forgotEmailController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  // ─── Supabase ────────────────────────────────────────────
  final _supabase = Supabase.instance.client;

  // ─── Biometrics ──────────────────────────────────────────
  final _localAuth = LocalAuthentication();
  bool _biometricsAvailable = false;

  // ─── Animations ──────────────────────────────────────────
  late AnimationController _glowController;
  late Animation<double> _glowAnimation;

  @override
  void initState() {
    super.initState();
    _isSignIn = !widget.showRegister;
    _glowController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat(reverse: true);
    _glowAnimation = Tween<double>(begin: 0.3, end: 0.7).animate(
      CurvedAnimation(parent: _glowController, curve: Curves.easeInOut),
    );
    _checkBiometrics();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _secretController.dispose();
    _forgotEmailController.dispose();
    _glowController.dispose();
    super.dispose();
  }

  // ─── Biometrics ──────────────────────────────────────────
  Future<void> _checkBiometrics() async {
    try {
      final canCheck = await _localAuth.canCheckBiometrics;
      final isSupported = await _localAuth.isDeviceSupported();
      if (mounted) {
        setState(
          () => _biometricsAvailable = !kIsWeb && canCheck && isSupported,
        );
      }
    } catch (e) {
      debugPrint('Biometrics check error: $e');
    }
  }

  Future<void> _authenticateWithBiometrics() async {
    try {
      final authenticated = await _localAuth.authenticate(
        localizedReason: 'Authenticate to sign in to Code Lab 3D',
        options: const AuthenticationOptions(
          biometricOnly: false,
          stickyAuth: true,
        ),
      );
      if (authenticated && mounted) {
        // Get last signed-in user from Supabase session
        final session = _supabase.auth.currentSession;
        if (session != null) {
          _navigateToDashboard(session.user.id);
        } else {
          _showError('No saved session. Please sign in with email first.');
        }
      }
    } catch (e) {
      if (mounted) _showError('Biometric authentication failed.');
    }
  }

  // ─── Auth Logic ──────────────────────────────────────────
  Future<void> _handleSubmit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);

    try {
      if (_isSignIn) {
        // ─── Sign In ───────────────────────────────────────
        final response = await _supabase.auth.signInWithPassword(
          email: _emailController.text.trim(),
          password: _passwordController.text.trim(),
        );
        if (response.user != null && mounted) {
          _navigateToDashboard(response.user!.id);
        }
      } else {
        // ─── Sign Up ───────────────────────────────────────
        if (!_isStudent) {
          final settings = await _supabase
              .from('app_settings')
              .select('value')
              .eq('key', 'faculty_secret_code')
              .single();
          if (_secretController.text.trim() != settings['value']) {
            throw 'Invalid faculty secret code.';
          }
        }

        final response = await _supabase.auth.signUp(
          email: _emailController.text.trim(),
          password: _passwordController.text.trim(),
        );

        if (response.user != null) {
          await _supabase.from('users').insert({
            'id': response.user!.id,
            'name': _nameController.text.trim(),
            'email': _emailController.text.trim(),
            'role': _isStudent ? 'student' : 'instructor',
            'sex': _isStudent ? _selectedSex : null,
            'xp': 0,
            'level': 1,
            'badges': [],
            'streak': 0,
            'created_at': DateTime.now().toIso8601String(),
          });

          if (mounted) {
            // Show success snackbar
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: const Row(
                  children: [
                    Icon(
                      Icons.check_circle_outline,
                      color: Colors.white,
                      size: 20,
                    ),
                    SizedBox(width: 10),
                    Text(
                      'Account Created! Please sign in.',
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                backgroundColor: Colors.green.shade700,
                behavior: SnackBarBehavior.floating,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                duration: const Duration(seconds: 2),
              ),
            );
            // Sign out to clear session, then redirect to Sign In tab
            await _supabase.auth.signOut();
            await Future.delayed(const Duration(milliseconds: 500));
            if (mounted) setState(() => _isSignIn = true);
          }
        }
      }
    } catch (e) {
      if (mounted) _showError(e.toString());
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _navigateToDashboard(String userId) async {
    final userData = await _supabase
        .from('users')
        .select('role')
        .eq('id', userId)
        .single();
    if (mounted) {
      context.go(
        userData['role'] == 'instructor'
            ? AppRoutes.instructorDashboard
            : AppRoutes.studentDashboard,
      );
    }
  }

  // ─── Forgot Password (2-step: Email → OTP → ResetPasswordScreen) ───
  void _showForgotPasswordDialog() {
    _forgotEmailController.clear();
    final otpController = TextEditingController();
    bool isSending = false;
    bool isVerifying = false;
    int step = 1; // 1 = enter email, 2 = enter OTP

    // Capture theme before dialog opens
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final dialogBg = isDark ? const Color(0xFF0D1B4B) : Colors.white;
    final borderColor = isDark
        ? const Color(0xFF1E3A6E)
        : const Color(0xFFDDE3F0);
    final fillColor = isDark
        ? const Color(0xFF0A1128)
        : const Color(0xFFF5F7FF);
    final textColor = isDark ? Colors.white : const Color(0xFF0D1B4B);
    final hintColor = isDark
        ? Colors.white.withValues(alpha: 0.5)
        : const Color(0xFF0D1B4B).withValues(alpha: 0.4);
    final iconColor = isDark
        ? Colors.white.withValues(alpha: 0.3)
        : const Color(0xFF0D1B4B).withValues(alpha: 0.4);
    final subtitleColor = isDark
        ? Colors.white.withValues(alpha: 0.6)
        : const Color(0xFF0D1B4B).withValues(alpha: 0.5);
    final cancelBg = isDark ? const Color(0xFF0A1128) : const Color(0xFFF0F4FF);
    final cancelTextColor = isDark
        ? Colors.white.withValues(alpha: 0.7)
        : const Color(0xFF0D1B4B).withValues(alpha: 0.7);

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialog) => Dialog(
          backgroundColor: dialogBg,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: BorderSide(color: borderColor),
          ),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ─── Header ──────────────────────────────
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E90FF).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        step == 1
                            ? Icons.lock_reset_outlined
                            : Icons.pin_outlined,
                        color: const Color(0xFF1E90FF),
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      step == 1 ? 'Forgot Password' : 'Enter OTP',
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: textColor,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  step == 1
                      ? 'Enter your email and we\'ll send you an OTP code.'
                      : 'Enter the OTP sent to\n${_forgotEmailController.text.trim()}',
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 12,
                    color: subtitleColor,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 20),

                // ─── Step 1: Email ─────────────────────────
                if (step == 1) ...[
                  TextFormField(
                    controller: _forgotEmailController,
                    keyboardType: TextInputType.emailAddress,
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      color: textColor,
                      fontSize: 14,
                    ),
                    decoration: InputDecoration(
                      labelText: 'Email Address',
                      labelStyle: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 13,
                        color: hintColor,
                      ),
                      floatingLabelStyle: const TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 12,
                        color: Color(0xFF1E90FF),
                        fontWeight: FontWeight.w600,
                      ),
                      prefixIcon: Icon(
                        Icons.email_outlined,
                        color: iconColor,
                        size: 20,
                      ),
                      filled: true,
                      fillColor: fillColor,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 16,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: borderColor),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: borderColor),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(
                          color: Color(0xFF1E90FF),
                          width: 1.5,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Expanded(
                        child: GestureDetector(
                          onTap: () => Navigator.pop(context),
                          child: Container(
                            height: 48,
                            decoration: BoxDecoration(
                              color: cancelBg,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: borderColor),
                            ),
                            child: Center(
                              child: Text(
                                'Cancel',
                                style: TextStyle(
                                  fontFamily: 'Poppins',
                                  color: cancelTextColor,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF1E90FF),
                            foregroundColor: Colors.white,
                            minimumSize: const Size(double.infinity, 48),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            elevation: 0,
                          ),
                          onPressed: isSending
                              ? null
                              : () async {
                                  final email = _forgotEmailController.text
                                      .trim();
                                  if (email.isEmpty || !email.contains('@')) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text('Enter a valid email.'),
                                        backgroundColor: Colors.red,
                                        behavior: SnackBarBehavior.floating,
                                      ),
                                    );
                                    return;
                                  }
                                  setDialog(() => isSending = true);
                                  try {
                                    await _supabase.auth.resetPasswordForEmail(
                                      email,
                                      redirectTo:
                                          'com.psulubao.it.lcms_app://reset-password',
                                    );
                                    setDialog(() {
                                      isSending = false;
                                      step = 2;
                                    });
                                    // Show bottom notification
                                    if (mounted) {
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        SnackBar(
                                          content: Row(
                                            children: [
                                              const Icon(
                                                Icons.mark_email_read_outlined,
                                                color: Colors.white,
                                                size: 18,
                                              ),
                                              const SizedBox(width: 10),
                                              Expanded(
                                                child: Text(
                                                  'OTP sent to $email 📧',
                                                  style: const TextStyle(
                                                    fontFamily: 'Poppins',
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                          backgroundColor:
                                              Colors.green.shade700,
                                          behavior: SnackBarBehavior.floating,
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(
                                              12,
                                            ),
                                          ),
                                          duration: const Duration(seconds: 3),
                                        ),
                                      );
                                    }
                                  } catch (e) {
                                    setDialog(() => isSending = false);
                                    if (mounted) {
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        SnackBar(
                                          content: Text('Error: $e'),
                                          backgroundColor: Colors.red,
                                          behavior: SnackBarBehavior.floating,
                                        ),
                                      );
                                    }
                                  }
                                },
                          child: isSending
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    color: Colors.white,
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Text(
                                  'Send OTP',
                                  style: TextStyle(
                                    fontFamily: 'Poppins',
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                        ),
                      ),
                    ],
                  ),
                ],

                // ─── Step 2: OTP Only ──────────────────────
                if (step == 2) ...[
                  TextFormField(
                    controller: otpController,
                    keyboardType: TextInputType.number,
                    maxLength: 8,
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      color: textColor,
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 8,
                    ),
                    textAlign: TextAlign.center,
                    decoration: InputDecoration(
                      labelText: 'OTP Code',
                      counterText: '',
                      labelStyle: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 13,
                        color: hintColor,
                      ),
                      floatingLabelStyle: const TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 12,
                        color: Color(0xFF1E90FF),
                        fontWeight: FontWeight.w600,
                      ),
                      prefixIcon: Icon(
                        Icons.pin_outlined,
                        color: iconColor,
                        size: 20,
                      ),
                      filled: true,
                      fillColor: fillColor,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 18,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: borderColor),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: borderColor),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(
                          color: Color(0xFF1E90FF),
                          width: 1.5,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Expanded(
                        child: GestureDetector(
                          onTap: () => setDialog(() => step = 1),
                          child: Container(
                            height: 48,
                            decoration: BoxDecoration(
                              color: cancelBg,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: borderColor),
                            ),
                            child: Center(
                              child: Text(
                                'Back',
                                style: TextStyle(
                                  fontFamily: 'Poppins',
                                  color: cancelTextColor,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF1E90FF),
                            foregroundColor: Colors.white,
                            minimumSize: const Size(double.infinity, 48),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            elevation: 0,
                          ),
                          onPressed: isVerifying
                              ? null
                              : () async {
                                  final otp = otpController.text.trim();
                                  if (otp.length < 6) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text(
                                          'Enter the complete OTP code.',
                                        ),
                                        backgroundColor: Colors.red,
                                        behavior: SnackBarBehavior.floating,
                                      ),
                                    );
                                    return;
                                  }
                                  setDialog(() => isVerifying = true);
                                  try {
                                    // Verify OTP — this creates a session
                                    await _supabase.auth.verifyOTP(
                                      email: _forgotEmailController.text.trim(),
                                      token: otp,
                                      type: OtpType.recovery,
                                    );
                                    // OTP correct — close dialog, go to ResetPasswordScreen
                                    if (mounted) {
                                      Navigator.pop(context);
                                      context.push(AppRoutes.resetPassword);
                                    }
                                  } catch (e) {
                                    setDialog(() => isVerifying = false);
                                    if (mounted) {
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        const SnackBar(
                                          content: Text(
                                            'Invalid OTP or expired. Try again.',
                                          ),
                                          backgroundColor: Colors.red,
                                          behavior: SnackBarBehavior.floating,
                                        ),
                                      );
                                    }
                                  }
                                },
                          child: isVerifying
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    color: Colors.white,
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Text(
                                  'Verify',
                                  style: TextStyle(
                                    fontFamily: 'Poppins',
                                    fontWeight: FontWeight.w700,
                                    fontSize: 15,
                                  ),
                                ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Center(
                    child: GestureDetector(
                      onTap: () async {
                        try {
                          await _supabase.auth.resetPasswordForEmail(
                            _forgotEmailController.text.trim(),
                            redirectTo:
                                'com.psulubao.it.lcms_app://reset-password',
                          );
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'New OTP sent! Check your email.',
                                ),
                                backgroundColor: Colors.blue,
                                behavior: SnackBarBehavior.floating,
                              ),
                            );
                          }
                        } catch (e) {
                          debugPrint('Resend: $e');
                        }
                      },
                      child: Text(
                        'Didn\'t receive it? Resend OTP',
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 12,
                          color: const Color(0xFF1E90FF).withValues(alpha: 0.8),
                          decoration: TextDecoration.underline,
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: const TextStyle(fontFamily: 'Poppins')),
        backgroundColor: Colors.red.shade800,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: isDark
              ? const RadialGradient(
                  center: Alignment(0, -0.3),
                  radius: 1.2,
                  colors: [Color(0xFF0D1B4B), Color(0xFF080D1F)],
                )
              : const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0xFFF0F4FF), Color(0xFFE8EEFF)],
                ),
        ),
        child: Stack(
          children: [
            _buildGridOverlay(size),
            if (isDark) _buildGlowEffect(size),
            SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 28),
                child: Form(
                  key: _formKey,
                  child: Column(
                    children: [
                      const SizedBox(height: 36),

                      // ─── Logo ──────────────────────────────
                      Image.asset(
                        'assets/images/logo.png',
                        width: size.width * 0.35,
                      ),

                      const SizedBox(height: 14),

                      // ─── Header Image ──────────────────────
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 400),
                        child: Image.asset(
                          _isSignIn
                              ? 'assets/images/welcome_text.png'
                              : 'assets/images/create_account_text.png',
                          key: ValueKey(_isSignIn),
                          width: size.width * 0.70,
                        ),
                      ),

                      const SizedBox(height: 26),

                      // ─── Sign In / Sign Up Toggle ──────────
                      _buildTabSwitcher(
                        leftLabel: 'Sign In',
                        rightLabel: 'Sign Up',
                        isLeftActive: _isSignIn,
                        onLeftTap: () => setState(() => _isSignIn = true),
                        onRightTap: () => setState(() => _isSignIn = false),
                      ),

                      const SizedBox(height: 22),

                      AnimatedSize(
                        duration: const Duration(milliseconds: 400),
                        curve: Curves.easeInOutCubic,
                        child: Column(
                          children: [
                            // ─── Role Tab (Sign Up only) ───────
                            _animatedField(
                              isVisible: !_isSignIn,
                              child: Padding(
                                padding: const EdgeInsets.only(bottom: 20),
                                child: _buildTabSwitcher(
                                  leftLabel: 'Student',
                                  rightLabel: 'Instructor',
                                  isLeftActive: _isStudent,
                                  onLeftTap: () =>
                                      setState(() => _isStudent = true),
                                  onRightTap: () =>
                                      setState(() => _isStudent = false),
                                ),
                              ),
                            ),

                            // ─── Full Name (Sign Up only) ──────
                            _animatedField(
                              isVisible: !_isSignIn,
                              child: _buildField(
                                label: 'Full Name',
                                controller: _nameController,
                                icon: Icons.person_outline,
                                validator: (v) {
                                  if (!_isSignIn && (v == null || v.isEmpty)) {
                                    return 'Enter your full name';
                                  }
                                  return null;
                                },
                              ),
                            ),

                            // ─── Sex Radio Buttons (Student Sign Up only) ─
                            _animatedField(
                              isVisible: !_isSignIn && _isStudent,
                              child: Padding(
                                padding: const EdgeInsets.only(bottom: 18),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 12,
                                  ),
                                  decoration: BoxDecoration(
                                    color: isDark
                                        ? const Color(0xFF0A1128)
                                        : Colors.white,
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: isDark
                                          ? const Color(0xFF1E3A6E)
                                          : const Color(0xFFDDE3F0),
                                    ),
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Icon(
                                            Icons.wc_outlined,
                                            color: isDark
                                                ? Colors.white.withValues(
                                                    alpha: 0.3,
                                                  )
                                                : const Color(
                                                    0xFF0D1B4B,
                                                  ).withValues(alpha: 0.4),
                                            size: 20,
                                          ),
                                          const SizedBox(width: 10),
                                          Text(
                                            'Sex',
                                            style: TextStyle(
                                              fontFamily: 'Poppins',
                                              fontSize: 13,
                                              color: isDark
                                                  ? Colors.white.withValues(
                                                      alpha: 0.5,
                                                    )
                                                  : const Color(
                                                      0xFF0D1B4B,
                                                    ).withValues(alpha: 0.4),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 8),
                                      Row(
                                        children: [
                                          // Male
                                          Expanded(
                                            child: GestureDetector(
                                              onTap: () => setState(
                                                () => _selectedSex = 'male',
                                              ),
                                              child: AnimatedContainer(
                                                duration: const Duration(
                                                  milliseconds: 200,
                                                ),
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      vertical: 10,
                                                    ),
                                                decoration: BoxDecoration(
                                                  color: _selectedSex == 'male'
                                                      ? const Color(
                                                          0xFF1E90FF,
                                                        ).withValues(
                                                          alpha: 0.15,
                                                        )
                                                      : Colors.transparent,
                                                  borderRadius:
                                                      BorderRadius.circular(10),
                                                  border: Border.all(
                                                    color:
                                                        _selectedSex == 'male'
                                                        ? const Color(
                                                            0xFF1E90FF,
                                                          )
                                                        : (isDark
                                                              ? const Color(
                                                                  0xFF1E3A6E,
                                                                )
                                                              : const Color(
                                                                  0xFFDDE3F0,
                                                                )), // FIXED BORDER
                                                  ),
                                                ),
                                                child: Row(
                                                  mainAxisAlignment:
                                                      MainAxisAlignment.center,
                                                  children: [
                                                    Radio<String>(
                                                      value: 'male',
                                                      groupValue: _selectedSex,
                                                      onChanged: (v) =>
                                                          setState(
                                                            () => _selectedSex =
                                                                v!,
                                                          ),
                                                      activeColor: const Color(
                                                        0xFF1E90FF,
                                                      ),
                                                      materialTapTargetSize:
                                                          MaterialTapTargetSize
                                                              .shrinkWrap,
                                                    ),
                                                    Text(
                                                      '♂ Male', // REMOVED const
                                                      style: TextStyle(
                                                        fontFamily: 'Poppins',
                                                        fontSize: 14,
                                                        // FIXED COLOR: White in Dark, Dark Blue in Light
                                                        color: isDark
                                                            ? Colors.white
                                                            : const Color(
                                                                0xFF0D1B4B,
                                                              ),
                                                        fontWeight:
                                                            FontWeight.w500,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 12),
                                          // Female
                                          Expanded(
                                            child: GestureDetector(
                                              onTap: () => setState(
                                                () => _selectedSex = 'female',
                                              ),
                                              child: AnimatedContainer(
                                                duration: const Duration(
                                                  milliseconds: 200,
                                                ),
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      vertical: 10,
                                                    ),
                                                decoration: BoxDecoration(
                                                  color:
                                                      _selectedSex == 'female'
                                                      ? const Color(
                                                          0xFFFF69B4,
                                                        ).withValues(
                                                          alpha: 0.15,
                                                        )
                                                      : Colors.transparent,
                                                  borderRadius:
                                                      BorderRadius.circular(10),
                                                  border: Border.all(
                                                    color:
                                                        _selectedSex == 'female'
                                                        ? const Color(
                                                            0xFFFF69B4,
                                                          )
                                                        : (isDark
                                                              ? const Color(
                                                                  0xFF1E3A6E,
                                                                )
                                                              : const Color(
                                                                  0xFFDDE3F0,
                                                                )), // FIXED BORDER
                                                  ),
                                                ),
                                                child: Row(
                                                  mainAxisAlignment:
                                                      MainAxisAlignment.center,
                                                  children: [
                                                    Radio<String>(
                                                      value: 'female',
                                                      groupValue: _selectedSex,
                                                      onChanged: (v) =>
                                                          setState(
                                                            () => _selectedSex =
                                                                v!,
                                                          ),
                                                      activeColor: const Color(
                                                        0xFFFF69B4,
                                                      ),
                                                      materialTapTargetSize:
                                                          MaterialTapTargetSize
                                                              .shrinkWrap,
                                                    ),
                                                    Text(
                                                      '♀ Female', // REMOVED const
                                                      style: TextStyle(
                                                        fontFamily: 'Poppins',
                                                        fontSize: 14,
                                                        // FIXED COLOR: White in Dark, Dark Blue in Light
                                                        color: isDark
                                                            ? Colors.white
                                                            : const Color(
                                                                0xFF0D1B4B,
                                                              ),
                                                        fontWeight:
                                                            FontWeight.w500,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),

                            // ─── Email ─────────────────────────
                            _buildField(
                              label: _isSignIn
                                  ? 'Email Address'
                                  : _isStudent
                                  ? 'Student Email Address'
                                  : 'Faculty Email Address',
                              controller: _emailController,
                              icon: Icons.email_outlined,
                              keyboardType: TextInputType.emailAddress,
                              validator: (v) {
                                if (v == null || v.isEmpty) {
                                  return 'Enter your email';
                                }
                                if (!v.contains('@')) {
                                  return 'Enter a valid email';
                                }
                                return null;
                              },
                            ),

                            // ─── Faculty Secret Code ───────────
                            _animatedField(
                              isVisible: !_isSignIn && !_isStudent,
                              child: _buildField(
                                label: 'Faculty Secret Code',
                                controller: _secretController,
                                icon: Icons.verified_user_outlined,
                                isPassword: true,
                                passwordVisible: _secretVisible,
                                onToggle: () => setState(
                                  () => _secretVisible = !_secretVisible,
                                ),
                                validator: (v) {
                                  if (!_isSignIn &&
                                      !_isStudent &&
                                      (v == null || v.isEmpty)) {
                                    return 'Enter the faculty secret code';
                                  }
                                  return null;
                                },
                              ),
                            ),

                            // ─── Password ──────────────────────
                            _buildField(
                              label: 'Password',
                              controller: _passwordController,
                              icon: Icons.lock_outline,
                              isPassword: true,
                              passwordVisible: _passwordVisible,
                              onToggle: () => setState(
                                () => _passwordVisible = !_passwordVisible,
                              ),
                              validator: (v) {
                                if (v == null || v.isEmpty) {
                                  return 'Enter your password';
                                }
                                if (v.length < 6) {
                                  return 'At least 6 characters';
                                }
                                return null;
                              },
                            ),

                            // ─── Confirm Password (Sign Up only) ─
                            _animatedField(
                              isVisible: !_isSignIn,
                              child: _buildField(
                                label: 'Confirm Password',
                                controller: _confirmPasswordController,
                                icon: Icons.lock_outline,
                                isPassword: true,
                                passwordVisible: _confirmPasswordVisible,
                                onToggle: () => setState(
                                  () => _confirmPasswordVisible =
                                      !_confirmPasswordVisible,
                                ),
                                validator: (v) {
                                  if (!_isSignIn) {
                                    if (v == null || v.isEmpty) {
                                      return 'Confirm your password';
                                    }
                                    if (v != _passwordController.text) {
                                      return 'Passwords do not match';
                                    }
                                  }
                                  return null;
                                },
                              ),
                            ),

                            // ─── Forgot Password (Sign In only) ─
                            _animatedField(
                              isVisible: _isSignIn,
                              child: Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: Align(
                                  alignment: Alignment.centerRight,
                                  child: GestureDetector(
                                    onTap: _showForgotPasswordDialog,
                                    child: const Text(
                                      'Forgot Password?',
                                      style: TextStyle(
                                        fontFamily: 'Poppins',
                                        fontSize: 13,
                                        color: Color(0xFF1E90FF),
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 12),

                      // ─── Submit Button ─────────────────────
                      _buildActionButton(),

                      // ─── Biometrics Button (Sign In only) ─
                      if (_isSignIn && _biometricsAvailable) ...[
                        const SizedBox(height: 16),
                        GestureDetector(
                          onTap: _authenticateWithBiometrics,
                          child: Container(
                            width: double.infinity,
                            height: 52,
                            decoration: BoxDecoration(
                              color: isDark
                                  ? const Color(0xFF0A1128)
                                  : Colors.white,
                              borderRadius: BorderRadius.circular(32),
                              border: Border.all(
                                color: isDark
                                    ? const Color(0xFF1E3A6E)
                                    : const Color(0xFFDDE3F0),
                              ),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.fingerprint,
                                  color: isDark
                                      ? Colors.white.withValues(alpha: 0.7)
                                      : const Color(
                                          0xFF0D1B4B,
                                        ).withValues(alpha: 0.7),
                                  size: 24,
                                ),
                                const SizedBox(width: 10),
                                Text(
                                  'Sign in with Biometrics',
                                  style: TextStyle(
                                    fontFamily: 'Poppins',
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: isDark
                                        ? Colors.white.withValues(alpha: 0.7)
                                        : const Color(
                                            0xFF0D1B4B,
                                          ).withValues(alpha: 0.7),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],

                      const SizedBox(height: 40),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _animatedField({required bool isVisible, required Widget child}) {
    return AnimatedSize(
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeInOutCubic,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 300),
        opacity: isVisible ? 1.0 : 0.0,
        child: isVisible
            ? child
            : const SizedBox(width: double.infinity, height: 0),
      ),
    );
  }

  Widget _buildField({
    required String label,
    required TextEditingController controller,
    required IconData icon,
    bool isPassword = false,
    bool passwordVisible = false,
    VoidCallback? onToggle,
    TextInputType keyboardType = TextInputType.text,
    String? Function(String?)? validator,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : const Color(0xFF0D1B4B);
    final fillColor = isDark ? const Color(0xFF0A1128) : Colors.white;
    final borderColor = isDark
        ? const Color(0xFF1E3A6E)
        : const Color(0xFFDDE3F0);
    final hintColor = isDark
        ? Colors.white.withValues(alpha: 0.5)
        : const Color(0xFF0D1B4B).withValues(alpha: 0.4);
    final iconColor = isDark
        ? Colors.white.withValues(alpha: 0.3)
        : const Color(0xFF0D1B4B).withValues(alpha: 0.4);

    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: TextFormField(
        controller: controller,
        obscureText: isPassword && !passwordVisible,
        keyboardType: keyboardType,
        validator: validator,
        style: TextStyle(fontFamily: 'Poppins', color: textColor, fontSize: 14),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: TextStyle(
            fontFamily: 'Poppins',
            fontSize: 13,
            color: hintColor,
          ),
          floatingLabelStyle: const TextStyle(
            fontFamily: 'Poppins',
            fontSize: 12,
            color: Color(0xFF1E90FF),
            fontWeight: FontWeight.w600,
          ),
          prefixIcon: Icon(icon, color: iconColor, size: 20),
          filled: true,
          fillColor: fillColor,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 18,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: borderColor, width: 1),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: borderColor, width: 1),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFF1E90FF), width: 1.5),
          ),
          errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Colors.redAccent, width: 1),
          ),
          focusedErrorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Colors.redAccent, width: 1.5),
          ),
          errorStyle: const TextStyle(
            fontFamily: 'Poppins',
            color: Colors.redAccent,
            fontSize: 11,
          ),
          suffixIcon: isPassword
              ? IconButton(
                  icon: Icon(
                    passwordVisible
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                    color: iconColor,
                    size: 20,
                  ),
                  onPressed: onToggle,
                )
              : null,
        ),
      ),
    );
  }

  Widget _buildTabSwitcher({
    required String leftLabel,
    required String rightLabel,
    required bool isLeftActive,
    required VoidCallback onLeftTap,
    required VoidCallback onRightTap,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      height: 48,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0A1128) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? const Color(0xFF1E3A6E) : const Color(0xFFDDE3F0),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          _buildTab(leftLabel, isLeftActive, onLeftTap),
          _buildTab(rightLabel, !isLeftActive, onRightTap),
        ],
      ),
    );
  }

  Widget _buildTab(String label, bool isActive, VoidCallback onTap) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final inactiveColor = isDark
        ? Colors.white.withValues(alpha: 0.5)
        : const Color(0xFF0D1B4B).withValues(alpha: 0.5);
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          margin: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            gradient: isActive
                ? const LinearGradient(
                    colors: [Color(0xFF1565C0), Color(0xFF1E90FF)],
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                  )
                : null,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 14,
                fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                color: isActive ? Colors.white : inactiveColor,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildActionButton() {
    return AnimatedBuilder(
      animation: _glowAnimation,
      builder: (context, child) => GestureDetector(
        onTap: _isLoading ? null : _handleSubmit,
        child: Container(
          width: double.infinity,
          height: 56,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF1565C0), Color(0xFF1E90FF)],
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
            ),
            borderRadius: BorderRadius.circular(32),
            boxShadow: [
              BoxShadow(
                color: const Color(
                  0xFF1E90FF,
                ).withValues(alpha: _glowAnimation.value * 0.5),
                blurRadius: 16,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Center(
            child: _isLoading
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 2.5,
                    ),
                  )
                : Text(
                    _isSignIn ? 'Sign In' : 'Sign Up',
                    style: const TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                      letterSpacing: 0.5,
                    ),
                  ),
          ),
        ),
      ),
    );
  }

  Widget _buildGridOverlay(Size size) {
    return Opacity(
      opacity: 0.04,
      child: CustomPaint(size: size, painter: _GridPainter()),
    );
  }

  Widget _buildGlowEffect(Size size) {
    return Positioned(
      top: -60,
      left: size.width * 0.5 - 120,
      child: AnimatedBuilder(
        animation: _glowAnimation,
        builder: (context, child) => Container(
          width: 240,
          height: 240,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: const Color(
                  0xFF1E90FF,
                ).withValues(alpha: _glowAnimation.value * 0.5),
                blurRadius: 100,
                spreadRadius: 30,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white
      ..strokeWidth = 0.5;
    const spacing = 30.0;
    for (double x = 0; x < size.width; x += spacing) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y < size.height; y += spacing) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
