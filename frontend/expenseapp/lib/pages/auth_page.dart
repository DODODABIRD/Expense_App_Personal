import 'dart:math' as math;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/auth_service.dart';
import '../widgets/neo_animations.dart';

class AuthPage extends StatefulWidget {
  const AuthPage({super.key});

  @override
  State<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<AuthPage> with TickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirmPassword = TextEditingController();

  bool _registering = false;
  bool _busy = false;
  bool _obscurePassword = true;
  bool _obscureConfirmation = true;
  String? _error;

  // Animation controllers for rich visuals
  late final AnimationController _floatingController;
  late final AnimationController _shakeController;
  late final Animation<double> _shakeAnimation;

  @override
  void initState() {
    super.initState();
    _floatingController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat(reverse: true);

    _shakeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );

    _shakeAnimation = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: -10.0), weight: 1),
      TweenSequenceItem(tween: Tween(begin: -10.0, end: 10.0), weight: 2),
      TweenSequenceItem(tween: Tween(begin: 10.0, end: -7.0), weight: 2),
      TweenSequenceItem(tween: Tween(begin: -7.0, end: 7.0), weight: 2),
      TweenSequenceItem(tween: Tween(begin: 7.0, end: 0.0), weight: 1),
    ]).animate(CurvedAnimation(parent: _shakeController, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _confirmPassword.dispose();
    _floatingController.dispose();
    _shakeController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) {
      _shakeController.forward(from: 0.0);
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      if (_registering) {
        await AuthService.register(_email.text, _password.text);
      } else {
        await AuthService.signIn(_email.text, _password.text);
      }
    } on FirebaseAuthException catch (error) {
      if (mounted) {
        setState(() => _error = _friendlyError(error));
        _shakeController.forward(from: 0.0);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _error = 'Terjadi kesalahan. Silakan coba lagi.');
        _shakeController.forward(from: 0.0);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _friendlyError(FirebaseAuthException error) {
    switch (error.code) {
      case 'invalid-credential':
      case 'invalid-login-credentials':
      case 'user-not-found':
      case 'wrong-password':
        return 'Email atau password salah. Cek lagi ya!';
      case 'email-already-in-use':
        return 'Email sudah terdaftar. Silakan login!';
      case 'weak-password':
        return 'Password terlalu pendek (minimal 6 karakter).';
      case 'invalid-email':
        return 'Format email tidak valid.';
      case 'network-request-failed':
        return 'Koneksi internet bermasalah. Coba lagi!';
      case 'too-many-requests':
        return 'Terlalu banyak percobaan. Tunggu beberapa saat.';
      default:
        return error.message ?? 'Autentikasi gagal. Silakan coba lagi.';
    }
  }

  String? _validateEmail(String? value) {
    final email = value?.trim() ?? '';
    if (email.isEmpty) return 'Email tidak boleh kosong';
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) {
      return 'Format email salah (contoh@email.com)';
    }
    return null;
  }

  String? _validatePassword(String? value) {
    if (value == null || value.isEmpty) return 'Password tidak boleh kosong';
    if (value.length < 6) return 'Password minimal 6 karakter';
    return null;
  }

  void _showForgotPasswordDialog() {
    final resetEmailController = TextEditingController(text: _email.text);
    bool isSending = false;
    String? resetError;
    String? resetSuccess;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          final isDark = Theme.of(ctx).brightness == Brightness.dark;
          final sheetBg = isDark ? const Color(0xFF1E1E1E) : Colors.white;

          return Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(ctx).viewInsets.bottom,
            ),
            child: Container(
              margin: const EdgeInsets.all(16),
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                color: sheetBg,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: Colors.black, width: 3),
                boxShadow: const [
                  BoxShadow(
                    color: Colors.black,
                    offset: Offset(6, 6),
                    blurRadius: 0,
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF9EB5D),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.black, width: 2),
                        ),
                        child: const Icon(Icons.lock_reset_rounded, color: Colors.black, size: 24),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Reset Password 🔑',
                              style: GoogleFonts.itim(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: isDark ? Colors.white : Colors.black,
                              ),
                            ),
                            Text(
                              'Kami kirim link reset ke email kamu',
                              style: TextStyle(
                                fontSize: 12,
                                color: isDark ? Colors.grey[400] : Colors.grey[700],
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(ctx),
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  if (resetSuccess != null) ...[
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: const Color(0xFF06D6A0).withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: const Color(0xFF06D6A0), width: 2),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.check_circle_rounded, color: Color(0xFF06D6A0)),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              resetSuccess!,
                              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                  ] else ...[
                    TextFormField(
                      controller: resetEmailController,
                      keyboardType: TextInputType.emailAddress,
                      style: TextStyle(color: isDark ? Colors.white : Colors.black),
                      decoration: InputDecoration(
                        labelText: 'Email Akun',
                        hintText: 'nama@domain.com',
                        prefixIcon: const Icon(Icons.email_outlined, color: Colors.black),
                        filled: true,
                        fillColor: isDark ? const Color(0xFF2A2A2A) : const Color(0xFFF4F7FB),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: const BorderSide(color: Colors.black, width: 2),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: const BorderSide(color: Color(0xFF5DF9FF), width: 2.5),
                        ),
                      ),
                    ),
                    if (resetError != null) ...[
                      const SizedBox(height: 10),
                      Text(
                        resetError!,
                        style: const TextStyle(color: Color(0xFFFF5D5D), fontSize: 12, fontWeight: FontWeight.bold),
                      ),
                    ],
                    const SizedBox(height: 18),
                    NeoButton(
                      text: 'KIRIM LINK RESET',
                      icon: Icons.send_rounded,
                      backgroundColor: const Color(0xFF5DF9FF),
                      isLoading: isSending,
                      onPressed: isSending
                          ? null
                          : () async {
                              final emailText = resetEmailController.text.trim();
                              if (emailText.isEmpty || !emailText.contains('@')) {
                                setSheetState(() => resetError = 'Masukkan email yang valid!');
                                return;
                              }
                              setSheetState(() {
                                isSending = true;
                                resetError = null;
                              });
                              try {
                                await AuthService.sendPasswordReset(emailText);
                                setSheetState(() {
                                  isSending = false;
                                  resetSuccess = 'Link reset berhasil dikirim! Silakan periksa inbox/spam email kamu.';
                                });
                              } on FirebaseAuthException catch (err) {
                                setSheetState(() {
                                  isSending = false;
                                  resetError = _friendlyError(err);
                                });
                              } catch (_) {
                                setSheetState(() {
                                  isSending = false;
                                  resetError = 'Gagal mengirim email reset. Coba sesaat lagi.';
                                });
                              }
                            },
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF14171A) : const Color(0xFFF4F7FB);

    return Scaffold(
      backgroundColor: bgColor,
      body: Stack(
        children: [
          // Animated floating decorative stickers in background
          _buildAnimatedBackground(isDark),

          // Main scrollable content
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 440),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const SizedBox(height: 10),

                      // Brand Hero Header
                      FadeSlideAnimation(
                        delay: const Duration(milliseconds: 100),
                        child: _buildHeroHeader(isDark),
                      ),

                      const SizedBox(height: 24),

                      // Mode Switcher (Sign In vs Register Tab)
                      FadeSlideAnimation(
                        delay: const Duration(milliseconds: 200),
                        child: _buildModeSwitcher(isDark),
                      ),

                      const SizedBox(height: 20),

                      // Animated Shakeable Neobrutalist Auth Card
                      FadeSlideAnimation(
                        delay: const Duration(milliseconds: 300),
                        child: AnimatedBuilder(
                          animation: _shakeAnimation,
                          builder: (context, child) {
                            return Transform.translate(
                              offset: Offset(_shakeAnimation.value, 0),
                              child: child,
                            );
                          },
                          child: _buildAuthCard(isDark),
                        ),
                      ),

                      const SizedBox(height: 24),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAnimatedBackground(bool isDark) {
    return AnimatedBuilder(
      animation: _floatingController,
      builder: (context, child) {
        final val = _floatingController.value;
        final float1 = math.sin(val * 2 * math.pi) * 8;
        final float2 = math.cos(val * 2 * math.pi) * 10;
        final rotate = math.sin(val * 2 * math.pi) * 0.08;

        return IgnorePointer(
          child: Stack(
            children: [
              // Top Right Floating Sticker (💸 Rp)
              Positioned(
                top: 40 + float1,
                right: 18,
                child: Transform.rotate(
                  angle: 0.15 + rotate,
                  child: _buildStickerBadge('💸 HEDON', const Color(0xFFF9EB5D), isDark),
                ),
              ),

              // Top Left Floating Sticker (⭐ TRACK)
              Positioned(
                top: 70 + float2,
                left: 14,
                child: Transform.rotate(
                  angle: -0.2 - rotate,
                  child: _buildStickerBadge('⭐ SMART', const Color(0xFF5DF9FF), isDark),
                ),
              ),

              // Center Left Floating Sticker (🔥 HEMAT)
              Positioned(
                bottom: 120 + float1,
                left: 12,
                child: Transform.rotate(
                  angle: 0.2 + rotate,
                  child: _buildStickerBadge('🔥 REKAP', const Color(0xFFFF5D5D), isDark, textColor: Colors.white),
                ),
              ),

              // Bottom Right Floating Sticker (🍕 GAUL)
              Positioned(
                bottom: 80 + float2,
                right: 16,
                child: Transform.rotate(
                  angle: -0.15 - rotate,
                  child: _buildStickerBadge('✨ UNMURCE', const Color(0xFF06D6A0), isDark),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildStickerBadge(String text, Color color, bool isDark, {Color textColor = Colors.black}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.black, width: 2),
        boxShadow: const [
          BoxShadow(
            color: Colors.black,
            offset: Offset(3, 3),
            blurRadius: 0,
          ),
        ],
      ),
      child: Text(
        text,
        style: GoogleFonts.itim(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          color: textColor,
          letterSpacing: 0.8,
        ),
      ),
    );
  }

  Widget _buildHeroHeader(bool isDark) {
    return Column(
      children: [
        // App Icon with Neobrutalism Frame & Interactive Spring Bounce
        NeoBouncy(
          scaleFactor: 0.92,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                width: 96,
                height: 96,
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: const Color(0xFF5DF9FF),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: Colors.black, width: 3),
                  boxShadow: const [
                    BoxShadow(
                      color: Colors.black,
                      offset: Offset(5, 5),
                      blurRadius: 0,
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(17),
                  child: Image.asset(
                    'assets/appiconv2.jpg',
                    fit: BoxFit.cover,
                  ),
                ),
              ),
              // Corner Sparkle Badge
              Positioned(
                top: -6,
                right: -6,
                child: Container(
                  padding: const EdgeInsets.all(5),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF9EB5D),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.black, width: 2),
                    boxShadow: const [
                      BoxShadow(
                        color: Colors.black,
                        offset: Offset(2, 2),
                        blurRadius: 0,
                      ),
                    ],
                  ),
                  child: const Icon(Icons.auto_awesome, size: 16, color: Colors.black),
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 16),

        // Brand Name Pill
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          decoration: BoxDecoration(
            color: const Color(0xFFF9EB5D),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.black, width: 2.5),
            boxShadow: const [
              BoxShadow(
                color: Colors.black,
                offset: Offset(3, 3),
                blurRadius: 0,
              ),
            ],
          ),
          child: Text(
            'UNMURCE',
            style: GoogleFonts.itim(
              color: Colors.black,
              fontSize: 28,
              fontWeight: FontWeight.bold,
              letterSpacing: 2,
            ),
          ),
        ),

        const SizedBox(height: 10),

        // Animated dynamic slogan
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          transitionBuilder: (child, animation) => FadeTransition(
            opacity: animation,
            child: SlideTransition(
              position: Tween<Offset>(begin: const Offset(0, 0.2), end: Offset.zero).animate(animation),
              child: child,
            ),
          ),
          child: Text(
            _registering
                ? 'Bikin akun supaya uang u ga abis 🔥'
                : 'Uangmu, bakal diganti papamu 💸',
            key: ValueKey<bool>(_registering),
            textAlign: TextAlign.center,
            style: GoogleFonts.itim(
              color: isDark ? const Color(0xFFB9D0DD) : const Color(0xFF475569),
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildModeSwitcher(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF22262B) : const Color(0xFFE2E8F0),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.black, width: 2.5),
        boxShadow: const [
          BoxShadow(
            color: Colors.black,
            offset: Offset(3, 3),
            blurRadius: 0,
          ),
        ],
      ),
      child: Row(
        children: [
          // Sign In Tab
          Expanded(
            child: NeoBouncy(
              onTap: () {
                if (_registering) {
                  setState(() {
                    _registering = false;
                    _error = null;
                  });
                }
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeInOut,
                padding: const EdgeInsets.symmetric(vertical: 11),
                decoration: BoxDecoration(
                  color: !_registering ? const Color(0xFF5DF9FF) : Colors.transparent,
                  borderRadius: BorderRadius.circular(13),
                  border: !_registering ? Border.all(color: Colors.black, width: 2) : null,
                  boxShadow: !_registering
                      ? const [
                          BoxShadow(
                            color: Colors.black,
                            offset: Offset(2, 2),
                            blurRadius: 0,
                          ),
                        ]
                      : null,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.login_rounded,
                      size: 19,
                      color: !_registering ? Colors.black : (isDark ? Colors.grey[400] : Colors.grey[600]),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'MASUK',
                      style: GoogleFonts.itim(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: !_registering ? Colors.black : (isDark ? Colors.grey[400] : Colors.grey[600]),
                        letterSpacing: 1.1,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          const SizedBox(width: 6),

          // Register Tab
          Expanded(
            child: NeoBouncy(
              onTap: () {
                if (!_registering) {
                  setState(() {
                    _registering = true;
                    _error = null;
                  });
                }
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeInOut,
                padding: const EdgeInsets.symmetric(vertical: 11),
                decoration: BoxDecoration(
                  color: _registering ? const Color(0xFFF9EB5D) : Colors.transparent,
                  borderRadius: BorderRadius.circular(13),
                  border: _registering ? Border.all(color: Colors.black, width: 2) : null,
                  boxShadow: _registering
                      ? const [
                          BoxShadow(
                            color: Colors.black,
                            offset: Offset(2, 2),
                            blurRadius: 0,
                          ),
                        ]
                      : null,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.person_add_rounded,
                      size: 19,
                      color: _registering ? Colors.black : (isDark ? Colors.grey[400] : Colors.grey[600]),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'DAFTAR',
                      style: GoogleFonts.itim(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: _registering ? Colors.black : (isDark ? Colors.grey[400] : Colors.grey[600]),
                        letterSpacing: 1.1,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAuthCard(bool isDark) {
    final cardBg = isDark ? const Color(0xFF1E1E1E) : Colors.white;

    return Container(
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: Colors.black, width: 3),
        boxShadow: const [
          BoxShadow(
            color: Colors.black,
            offset: Offset(6, 6),
            blurRadius: 0,
          ),
        ],
      ),
      padding: const EdgeInsets.all(22),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header Title with colored pill badge
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: _registering ? const Color(0xFFF9EB5D) : const Color(0xFF5DF9FF),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.black, width: 2),
                  ),
                  child: Text(
                    _registering ? 'AKUN BARU' : 'LOGIN',
                    style: GoogleFonts.itim(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: Colors.black,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _registering ? 'Daftar Sekarang ✨' : 'Selamat Datang! 👋',
                    style: GoogleFonts.itim(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white : Colors.black,
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 20),

            // Email Field
            _buildField(
              controller: _email,
              label: 'Email',
              hint: 'kamu@contoh.com',
              icon: Icons.alternate_email_rounded,
              iconColor: const Color(0xFF70D6FF),
              keyboardType: TextInputType.emailAddress,
              validator: _validateEmail,
              isDark: isDark,
            ),

            const SizedBox(height: 16),

            // Password Field
            _buildField(
              controller: _password,
              label: 'Password',
              hint: 'Minimal 6 karakter',
              icon: Icons.lock_outline_rounded,
              iconColor: const Color(0xFFFFD166),
              obscureText: _obscurePassword,
              validator: _validatePassword,
              isDark: isDark,
              suffixIcon: IconButton(
                tooltip: _obscurePassword ? 'Tampilkan password' : 'Sembunyikan password',
                onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                icon: Icon(
                  _obscurePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                  color: isDark ? Colors.grey[300] : Colors.grey[700],
                ),
              ),
            ),

            // Confirm Password Field with Smooth Animated Size expansion
            AnimatedSize(
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeInOut,
              child: _registering
                  ? Column(
                      children: [
                        const SizedBox(height: 16),
                        _buildField(
                          controller: _confirmPassword,
                          label: 'Konfirmasi Password',
                          hint: 'Ulangi password di atas',
                          icon: Icons.verified_user_outlined,
                          iconColor: const Color(0xFFC77DFF),
                          obscureText: _obscureConfirmation,
                          validator: (value) {
                            if (!_registering) return null;
                            if (value == null || value.isEmpty) {
                              return 'Konfirmasi password wajib diisi';
                            }
                            if (value != _password.text) {
                              return 'Password konfirmasi tidak cocok!';
                            }
                            return null;
                          },
                          isDark: isDark,
                          suffixIcon: IconButton(
                            tooltip: _obscureConfirmation ? 'Tampilkan password' : 'Sembunyikan password',
                            onPressed: () => setState(() => _obscureConfirmation = !_obscureConfirmation),
                            icon: Icon(
                              _obscureConfirmation ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                              color: isDark ? Colors.grey[300] : Colors.grey[700],
                            ),
                          ),
                        ),
                      ],
                    )
                  : const SizedBox.shrink(),
            ),

            // Forgot Password Link (only in Sign In mode)
            if (!_registering) ...[
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: _busy ? null : _showForgotPasswordDialog,
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: Text(
                    'Lupa Password? 🤔',
                    style: GoogleFonts.itim(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: isDark ? const Color(0xFF5DF9FF) : const Color(0xFF007A99),
                      decoration: TextDecoration.underline,
                    ),
                  ),
                ),
              ),
            ],

            // Error Message Banner with Neobrutal styling
            if (_error != null) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFFF5D5D),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.black, width: 2),
                  boxShadow: const [
                    BoxShadow(
                      color: Colors.black,
                      offset: Offset(3, 3),
                      blurRadius: 0,
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline_rounded, color: Colors.white, size: 22),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _error!,
                        style: GoogleFonts.itim(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 22),

            // Submit Button
            NeoButton(
              text: _registering ? 'DAFTAR SEKARANG 🚀' : 'MASUK KE APLIKASI ⚡',
              backgroundColor: _registering ? const Color(0xFFF9EB5D) : const Color(0xFF5DF9FF),
              textColor: Colors.black,
              borderWidth: 2.5,
              shadowOffset: 4,
              fontSize: 18,
              isLoading: _busy,
              onPressed: _busy ? null : _submit,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    required Color iconColor,
    required String? Function(String?) validator,
    required bool isDark,
    TextInputType? keyboardType,
    bool obscureText = false,
    Widget? suffixIcon,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: GoogleFonts.itim(
            fontSize: 15,
            fontWeight: FontWeight.bold,
            color: isDark ? Colors.white : Colors.black87,
          ),
        ),
        const SizedBox(height: 6),
        TextFormField(
          controller: controller,
          validator: validator,
          keyboardType: keyboardType,
          obscureText: obscureText,
          textInputAction: TextInputAction.next,
          style: TextStyle(
            color: isDark ? Colors.white : Colors.black,
            fontWeight: FontWeight.w600,
          ),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(
              color: isDark ? Colors.grey[500] : Colors.grey[400],
              fontSize: 14,
            ),
            prefixIcon: Padding(
              padding: const EdgeInsets.all(8.0),
              child: Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: iconColor,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.black, width: 2),
                ),
                child: Icon(icon, color: Colors.black, size: 18),
              ),
            ),
            suffixIcon: suffixIcon,
            filled: true,
            fillColor: isDark ? const Color(0xFF262626) : const Color(0xFFF7F9FC),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: const BorderSide(color: Colors.black, width: 2),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: const BorderSide(color: Colors.black, width: 2),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: const BorderSide(color: Color(0xFF5DF9FF), width: 2.8),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: const BorderSide(color: Color(0xFFFF5D5D), width: 2),
            ),
            focusedErrorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: const BorderSide(color: Color(0xFFFF5D5D), width: 2.8),
            ),
            errorStyle: GoogleFonts.itim(
              color: const Color(0xFFFF5D5D),
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ],
    );
  }
}