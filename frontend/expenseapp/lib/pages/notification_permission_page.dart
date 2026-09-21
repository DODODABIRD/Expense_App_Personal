import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/notification_expense_service.dart';
import '../widgets/neo_animations.dart';

class NotificationPermissionPage extends StatelessWidget {
  const NotificationPermissionPage({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF14191F) : const Color(0xFFF6F8FA);
    final cardBg = isDark ? const Color(0xFF1E2830) : Colors.white;

    return Scaffold(
      backgroundColor: bgColor,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
          child: Column(
            children: [
              const SizedBox(height: 12),
              // Top Badge
              Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFF5DF9FF),
                    borderRadius: BorderRadius.circular(100),
                    border: Border.all(color: Colors.black, width: 2.2),
                    boxShadow: const [
                      BoxShadow(
                        color: Colors.black,
                        offset: Offset(2.5, 2.5),
                        blurRadius: 0,
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.auto_awesome_rounded, size: 16, color: Colors.black),
                      const SizedBox(width: 6),
                      Text(
                        'OTOMATISASI PINTAR',
                        style: GoogleFonts.itim(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Colors.black,
                          letterSpacing: 0.8,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 24),

              // Main Illustration Card
              Expanded(
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(22),
                    decoration: BoxDecoration(
                      color: cardBg,
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: Colors.black, width: 2.8),
                      boxShadow: const [
                        BoxShadow(
                          color: Colors.black,
                          offset: Offset(5, 5),
                          blurRadius: 0,
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        // Icon Box
                        Container(
                          width: 88,
                          height: 88,
                          decoration: BoxDecoration(
                            color: const Color(0xFFF9EB5D),
                            borderRadius: BorderRadius.circular(22),
                            border: Border.all(color: Colors.black, width: 2.8),
                            boxShadow: const [
                              BoxShadow(
                                color: Colors.black,
                                offset: Offset(3.5, 3.5),
                                blurRadius: 0,
                              ),
                            ],
                          ),
                          child: const Icon(
                            Icons.notifications_active_rounded,
                            size: 46,
                            color: Colors.black,
                          ),
                        ),

                        const SizedBox(height: 18),

                        Text(
                          'Catat Pengeluaran Otomatis',
                          textAlign: TextAlign.center,
                          style: GoogleFonts.itim(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: isDark ? Colors.white : Colors.black,
                          ),
                        ),

                        const SizedBox(height: 8),

                        Text(
                          'Aplikasi dapat mendeteksi pembayaran dari bank dan e-wallet secara instan tanpa perlu repot mencatat manual.',
                          textAlign: TextAlign.center,
                          style: GoogleFonts.itim(
                            fontSize: 14,
                            color: isDark ? Colors.white70 : Colors.black87,
                            height: 1.35,
                          ),
                        ),

                        const SizedBox(height: 24),
                        const Divider(color: Colors.black26, height: 1),
                        const SizedBox(height: 20),

                        // Benefits List
                        _buildBenefitRow(
                          icon: Icons.flash_on_rounded,
                          iconBg: const Color(0xFF5DF9FF),
                          title: 'Deteksi Instan & Cepat',
                          description:
                              'Mendukung QRIS dan transfer dari BCA, Mandiri, BRI, BNI, GoPay, OVO, DANA, ShopeePay, dan lainnya.',
                          isDark: isDark,
                        ),
                        const SizedBox(height: 16),
                        _buildBenefitRow(
                          icon: Icons.shield_rounded,
                          iconBg: const Color(0xFF06D6A0),
                          title: '100% Aman & Privat',
                          description:
                              'Diproses secara lokal di perangkat Anda. Tidak pernah membaca SMS pribadi atau kode rahasia/OTP.',
                          isDark: isDark,
                        ),
                        const SizedBox(height: 16),
                        _buildBenefitRow(
                          icon: Icons.tune_rounded,
                          iconBg: const Color(0xFFFF99C8),
                          title: 'Kontrol Penuh',
                          description:
                              'Bisa memilih aplikasi mana saja yang diizinkan atau dinonaktifkan kapan saja di menu Pengaturan.',
                          isDark: isDark,
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // Action Buttons
              NeoBouncy(
                scaleFactor: 0.96,
                onTap: () async {
                  final service = NotificationExpenseService.instance;
                  await service.setParserEnabled(true);
                  await service.openAccessSettings();
                  if (context.mounted) {
                    Navigator.of(context).pop();
                  }
                },
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF9EB5D),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.black, width: 2.8),
                    boxShadow: const [
                      BoxShadow(
                        color: Colors.black,
                        offset: Offset(4, 4),
                        blurRadius: 0,
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.check_circle_rounded, color: Colors.black, size: 22),
                      const SizedBox(width: 8),
                      Text(
                        'Izinkan Akses Notifikasi',
                        style: GoogleFonts.itim(
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                          color: Colors.black,
                          letterSpacing: 0.4,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 10),

              NeoBouncy(
                scaleFactor: 0.96,
                onTap: () => Navigator.of(context).pop(),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF263238) : const Color(0xFFE8ECEF),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Colors.black, width: 2),
                  ),
                  child: Center(
                    child: Text(
                      'Nanti Saja',
                      style: GoogleFonts.itim(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white70 : Colors.black87,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBenefitRow({
    required IconData icon,
    required Color iconBg,
    required String title,
    required String description,
    required bool isDark,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(9),
          decoration: BoxDecoration(
            color: iconBg,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.black, width: 2),
            boxShadow: const [
              BoxShadow(
                color: Colors.black,
                offset: Offset(2, 2),
                blurRadius: 0,
              ),
            ],
          ),
          child: Icon(icon, size: 20, color: Colors.black),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: GoogleFonts.itim(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : Colors.black,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                description,
                style: GoogleFonts.itim(
                  fontSize: 13,
                  color: isDark ? Colors.white70 : Colors.black54,
                  height: 1.25,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
