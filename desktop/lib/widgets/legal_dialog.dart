// Usage:
//   LegalDialog.showTerms(context);
//   LegalDialog.showPrivacy(context);

import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Legal content
// ─────────────────────────────────────────────────────────────────────────────

const String _kAppName = 'RealFaceAI';
const String _kCompany = 'RealFaceAI';
const String _kEmail = 'support@realfaceai.app';
const String _kEffective = 'May 27, 2026';

// ── Terms of Use ─────────────────────────────────────────────────────────────

const List<_LegalSection> _kTermsSections = [
  _LegalSection(
      '1. Acceptance of Terms',
      'By creating an account or using $_kAppName, you agree to these Terms of Use. '
          'If you do not agree, do not use the platform. We may update these terms at any time; '
          'continued use after updates constitutes acceptance.'),
  _LegalSection(
      '2. Eligibility',
      'You must be at least 18 years old to use $_kAppName. By registering, you confirm '
          'that you meet this age requirement and that you are legally permitted to enter into '
          'this agreement in your jurisdiction.'),
  _LegalSection(
      '3. Account Responsibility',
      'You are responsible for maintaining the confidentiality of your account credentials. '
          'You are solely responsible for all activity that occurs under your account. '
          'Notify us immediately at $_kEmail if you suspect unauthorised access.'),
  _LegalSection(
      '4. Permitted Use',
      'You may use $_kAppName only for lawful purposes. You agree NOT to:\n\n'
          '• Use the platform to create non-consensual deepfakes or impersonate real people without their explicit consent.\n'
          '• Generate content that is defamatory, harassing, obscene, or fraudulent.\n'
          '• Attempt to reverse-engineer, scrape, or exploit the platform\'s infrastructure.\n'
          '• Resell or sublicense access to the platform without a written commercial agreement.\n'
          '• Use the platform in any way that violates applicable laws or regulations.'),
  _LegalSection(
      '5. AI-Generated Content',
      'All output produced by $_kAppName is AI-generated. You are solely responsible for '
          'how you use or distribute that output. We do not verify or endorse any content '
          'produced by users. You retain ownership of output you create, but grant us a limited '
          'licence to process and deliver it as part of the service.'),
  _LegalSection(
      '6. Credits and Payments',
      'Access to streaming and generation features requires purchasing credits. Credits are '
          'non-refundable once consumed. Unused credits do not expire but have no cash value. '
          'We reserve the right to adjust credit pricing at any time with reasonable notice.'),
  _LegalSection(
      '7. Crypto Payments',
      'We accept cryptocurrency payments (USDT/USDC on BSC and Solana). Cryptocurrency '
          'transactions are irreversible by nature. Once a deposit is confirmed on-chain, it '
          'cannot be reversed. You are responsible for sending funds to the correct address '
          'and network. We are not responsible for funds lost due to incorrect transfers.'),
  _LegalSection(
      '8. Service Availability',
      '$_kAppName is provided "as is". We do not guarantee 100% uptime or uninterrupted '
          'access. Scheduled and emergency maintenance may temporarily suspend the service. '
          'We are not liable for any losses resulting from service interruptions.'),
  _LegalSection(
      '9. Termination',
      'We may suspend or terminate your account at any time if you violate these terms, '
          'engage in fraudulent activity, or if we are required to do so by law. Upon '
          'termination, access to the platform and any unused credits is forfeited.'),
  _LegalSection(
      '10. Limitation of Liability',
      'To the maximum extent permitted by law, $_kCompany shall not be liable for any '
          'indirect, incidental, special, or consequential damages arising from your use of '
          'the platform, including but not limited to loss of data, revenue, or reputation.'),
  _LegalSection(
      '11. Governing Law',
      'These terms are governed by applicable international law. Disputes shall be resolved '
          'through binding arbitration where permitted, or in a competent court of jurisdiction.'),
  _LegalSection('12. Contact',
      'For questions about these Terms, contact us at:\n$_kEmail'),
];

// ── Privacy Policy ────────────────────────────────────────────────────────────

const List<_LegalSection> _kPrivacySections = [
  _LegalSection(
      '1. Introduction',
      'This Privacy Policy explains what personal data $_kCompany collects when you use '
          '$_kAppName, how we use it, and your rights regarding that data. '
          'By using the platform, you consent to the practices described here.'),
  _LegalSection(
      '2. Data We Collect',
      'When you register and use $_kAppName, we collect:\n\n'
          '• Email address and username (account creation)\n'
          '• Password (stored as a one-way hash — we never store your plain password)\n'
          '• IP address and device type (for security and fraud prevention)\n'
          '• Usage data (features used, credits consumed, session duration)\n'
          '• Payment records (transaction IDs and amounts — no card numbers are stored)\n'
          '• Images you upload for face swap features (processed in real-time and not stored permanently)\n\n'
          'We do NOT sell your personal data to third parties.'),
  _LegalSection(
      '3. How We Use Your Data',
      'We use your data to:\n\n'
          '• Provide and improve the $_kAppName service\n'
          '• Process payments and manage your credit balance\n'
          '• Detect and prevent fraudulent or abusive activity\n'
          '• Send important service notifications (not marketing without consent)\n'
          '• Comply with legal obligations'),
  _LegalSection(
      '4. Video and Image Processing',
      'When you use real-time face swap features, your webcam feed is processed live. '
          'We do not permanently store your raw video stream. Session data is used only to '
          'deliver the AI output back to you in real-time and is discarded after the session ends. '
          'Uploaded reference images are held only for the duration of your session.'),
  _LegalSection(
      '5. Third-Party Services',
      'We use third-party infrastructure to deliver our service, including AI processing '
          'providers and cloud hosting. These providers process data on our behalf under '
          'strict data processing agreements. We do not share your personal data with '
          'third parties for their own marketing purposes.'),
  _LegalSection(
      '6. Data Retention',
      'We retain your account data for as long as your account is active. '
          'If you delete your account, we will remove your personal data within 30 days, '
          'except where we are required by law to retain certain records (e.g. payment records '
          'for tax compliance, typically 7 years).'),
  _LegalSection(
      '7. Your Rights',
      'Depending on your jurisdiction, you may have the right to:\n\n'
          '• Access a copy of the personal data we hold about you\n'
          '• Correct inaccurate data\n'
          '• Request deletion of your data ("right to be forgotten")\n'
          '• Object to or restrict certain processing\n'
          '• Data portability\n\n'
          'To exercise any of these rights, contact us at $_kEmail.'),
  _LegalSection(
      '8. Security',
      'We implement industry-standard security measures including encrypted connections '
          '(HTTPS/TLS), hashed passwords, and server-side API key management. No system is '
          '100% secure; we cannot guarantee absolute security but take every reasonable '
          'precaution to protect your data.'),
  _LegalSection(
      '9. Cookies and Tracking',
      '$_kAppName is a desktop application. We do not use browser cookies. '
          'We may collect anonymised analytics (feature usage, error rates) to improve '
          'the product. This data is aggregated and cannot identify you personally.'),
  _LegalSection(
      '10. Children\'s Privacy',
      '$_kAppName is not intended for users under 18 years of age. We do not knowingly '
          'collect data from minors. If you believe a minor has registered, contact us at '
          '$_kEmail and we will delete the account.'),
  _LegalSection(
      '11. Changes to This Policy',
      'We may update this Privacy Policy from time to time. We will notify you of '
          'significant changes via email or an in-app notice. Continued use of the platform '
          'after changes constitutes acceptance of the updated policy.'),
  _LegalSection('12. Contact',
      'For any privacy-related questions or requests:\n$_kEmail'),
];

// ─────────────────────────────────────────────────────────────────────────────
// Data model
// ─────────────────────────────────────────────────────────────────────────────

class _LegalSection {
  final String heading;
  final String body;
  const _LegalSection(this.heading, this.body);
}

// ─────────────────────────────────────────────────────────────────────────────
// Public API
// ─────────────────────────────────────────────────────────────────────────────

class LegalDialog {
  LegalDialog._();

  static Future<void> showTerms(BuildContext context) => _show(
        context,
        title: 'Terms of Use',
        effective: _kEffective,
        sections: _kTermsSections,
      );

  static Future<void> showPrivacy(BuildContext context) => _show(
        context,
        title: 'Privacy Policy',
        effective: _kEffective,
        sections: _kPrivacySections,
      );

  static Future<void> _show(
    BuildContext context, {
    required String title,
    required String effective,
    required List<_LegalSection> sections,
  }) {
    return showDialog(
      context: context,
      barrierColor: Colors.black87,
      builder: (_) => _LegalDialogWidget(
        title: title,
        effective: effective,
        sections: sections,
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Dialog widget
// ─────────────────────────────────────────────────────────────────────────────

class _LegalDialogWidget extends StatefulWidget {
  final String title;
  final String effective;
  final List<_LegalSection> sections;

  const _LegalDialogWidget({
    required this.title,
    required this.effective,
    required this.sections,
  });

  @override
  State<_LegalDialogWidget> createState() => _LegalDialogWidgetState();
}

class _LegalDialogWidgetState extends State<_LegalDialogWidget> {
  final _scrollCtrl = ScrollController();
  bool _reachedBottom = false;

  @override
  void initState() {
    super.initState();
    _scrollCtrl.addListener(_onScroll);
  }

  void _onScroll() {
    if (_scrollCtrl.offset >= _scrollCtrl.position.maxScrollExtent - 40) {
      if (!_reachedBottom) setState(() => _reachedBottom = true);
    }
  }

  @override
  void dispose() {
    _scrollCtrl.removeListener(_onScroll);
    _scrollCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 32, vertical: 40),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 680,
          maxHeight: size.height * 0.82,
        ),
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.bgCard,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            children: [
              // ── Header ───────────────────────────────────────────────────
              Container(
                padding: const EdgeInsets.fromLTRB(24, 20, 16, 16),
                decoration: BoxDecoration(
                  border: Border(bottom: BorderSide(color: AppColors.border)),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: AppColors.goldGlow,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(Icons.gavel_rounded,
                          color: AppColors.gold, size: 16),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.title,
                            style: TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            'Effective: ${widget.effective}',
                            style: TextStyle(
                              color: AppColors.textMuted,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: Icon(Icons.close_rounded,
                          color: AppColors.textSecondary, size: 20),
                      style: IconButton.styleFrom(
                        backgroundColor: AppColors.bgElevated,
                        padding: const EdgeInsets.all(6),
                        minimumSize: const Size(32, 32),
                      ),
                    ),
                  ],
                ),
              ),

              // ── Scrollable content ────────────────────────────────────────
              Expanded(
                child: Scrollbar(
                  controller: _scrollCtrl,
                  thumbVisibility: true,
                  child: ListView.separated(
                    controller: _scrollCtrl,
                    padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
                    itemCount: widget.sections.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 20),
                    itemBuilder: (_, i) {
                      final s = widget.sections[i];
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            s.heading,
                            style: TextStyle(
                              color: AppColors.gold,
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.1,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            s.body,
                            style: TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 13,
                              height: 1.65,
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ),

              // ── Footer ───────────────────────────────────────────────────
              Container(
                padding: const EdgeInsets.fromLTRB(24, 14, 24, 18),
                decoration: BoxDecoration(
                  border: Border(top: BorderSide(color: AppColors.border)),
                ),
                child: Row(
                  children: [
                    if (!_reachedBottom) ...[
                      Icon(Icons.arrow_downward_rounded,
                          size: 13, color: AppColors.textMuted),
                      const SizedBox(width: 6),
                      Text(
                        'Scroll to read all',
                        style:
                            TextStyle(color: AppColors.textMuted, fontSize: 12),
                      ),
                      const Spacer(),
                    ] else ...[
                      Icon(Icons.check_circle_rounded,
                          size: 13, color: AppColors.success),
                      const SizedBox(width: 6),
                      Text(
                        'You\'ve read the full document',
                        style: TextStyle(
                            color: AppColors.textSecondary, fontSize: 12),
                      ),
                      const Spacer(),
                    ],
                    SizedBox(
                      height: 36,
                      child: ElevatedButton(
                        onPressed: () => Navigator.of(context).pop(),
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                        ),
                        child:
                            const Text('Close', style: TextStyle(fontSize: 13)),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
