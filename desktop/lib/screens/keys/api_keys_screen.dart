// import 'package:flutter/material.dart';
// import 'package:flutter_animate/flutter_animate.dart';
// import '../../models/api_key.dart';
// import '../../services/api_service.dart';
// import '../../theme/app_theme.dart';
// import '../../widgets/shared_widgets.dart';

// class ApiKeysScreen extends StatefulWidget {
//   const ApiKeysScreen({super.key});

//   @override
//   State<ApiKeysScreen> createState() => _ApiKeysScreenState();
// }

// class _ApiKeysScreenState extends State<ApiKeysScreen> {
//   List<ApiKeyModel> _keys = [];
//   bool _loading = true;
//   String? _newRawKey; // Shown once after creation

//   @override
//   void initState() {
//     super.initState();
//     _loadKeys();
//   }

//   Future<void> _loadKeys() async {
//     setState(() => _loading = true);
//     try {
//       final data = await ApiService.instance.getApiKeys();
//       setState(() {
//         _keys   = data.map((j) => ApiKeyModel.fromJson(j as Map<String, dynamic>)).toList();
//         _loading = false;
//       });
//     } catch (_) {
//       setState(() => _loading = false);
//     }
//   }

//   Future<void> _createKey() async {
//     final nameCtrl = TextEditingController(text: 'My Key');
//     final confirmed = await showDialog<bool>(
//       context: context,
//       builder: (_) => AlertDialog(
//         backgroundColor: AppColors.bgCard,
//         shape: RoundedRectangleBorder(
//           borderRadius: BorderRadius.circular(12),
//           side: const BorderSide(color: AppColors.border),
//         ),
//         title: const Text('Create API Key', style: TextStyle(color: AppColors.textPrimary)),
//         content: SizedBox(
//           width: 360,
//           child: Column(
//             mainAxisSize: MainAxisSize.min,
//             children: [
//               const Text(
//                 'Give your key a name to identify it later.',
//                 style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
//               ),
//               const SizedBox(height: 16),
//               TextField(
//                 controller: nameCtrl,
//                 decoration: const InputDecoration(labelText: 'Key name'),
//                 autofocus: true,
//               ),
//             ],
//           ),
//         ),
//         actions: [
//           TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
//           ElevatedButton(
//             onPressed: () => Navigator.pop(context, true),
//             child: const Text('Create'),
//           ),
//         ],
//       ),
//     );

//     if (confirmed != true) return;

//     final result = await ApiService.instance.createApiKey(nameCtrl.text.trim());
//     if (result['key'] != null) {
//       setState(() => _newRawKey = result['key'] as String);
//       await _loadKeys();
//     }
//   }

//   Future<void> _revokeKey(ApiKeyModel key) async {
//     final confirmed = await showDialog<bool>(
//       context: context,
//       builder: (_) => AlertDialog(
//         backgroundColor: AppColors.bgCard,
//         shape: RoundedRectangleBorder(
//           borderRadius: BorderRadius.circular(12),
//           side: const BorderSide(color: AppColors.border),
//         ),
//         title: const Text('Revoke Key', style: TextStyle(color: AppColors.textPrimary)),
//         content: Text(
//           'Revoke "${key.name}"?\nThis key will stop working immediately.',
//           style: const TextStyle(color: AppColors.textSecondary),
//         ),
//         actions: [
//           TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
//           ElevatedButton(
//             style: ElevatedButton.styleFrom(backgroundColor: AppColors.danger),
//             onPressed: () => Navigator.pop(context, true),
//             child: const Text('Revoke'),
//           ),
//         ],
//       ),
//     );

//     if (confirmed != true) return;
//     final ok = await ApiService.instance.revokeApiKey(key.id);
//     if (ok) _loadKeys();
//   }

//   @override
//   Widget build(BuildContext context) {
//     return Scaffold(
//       backgroundColor: AppColors.bg,
//       body: SingleChildScrollView(
//         padding: const EdgeInsets.all(32),
//         child: Column(
//           crossAxisAlignment: CrossAxisAlignment.start,
//           children: [
//             SectionHeader(
//               title: 'API Keys',
//               subtitle: 'Manage keys for accessing the streaming API',
//               action: PrimaryButton(
//                 label: 'New Key',
//                 icon: Icons.add_rounded,
//                 onPressed: _createKey,
//               ),
//             ).animate().fadeIn(),

//             const SizedBox(height: 24),

//             // New key reveal banner
//             if (_newRawKey != null)
//               Container(
//                 padding: const EdgeInsets.all(20),
//                 margin: const EdgeInsets.only(bottom: 20),
//                 decoration: BoxDecoration(
//                   color: AppColors.success.withValues(alpha: 0.08),
//                   borderRadius: BorderRadius.circular(12),
//                   border: Border.all(color: AppColors.success.withValues(alpha: 0.3)),
//                 ),
//                 child: Column(
//                   crossAxisAlignment: CrossAxisAlignment.start,
//                   children: [
//                     const Row(
//                       children: [
//                         Icon(Icons.check_circle_rounded, color: AppColors.success, size: 18),
//                         SizedBox(width: 8),
//                         Text(
//                           'Key created — copy it now!',
//                           style: TextStyle(color: AppColors.success, fontWeight: FontWeight.w600),
//                         ),
//                       ],
//                     ),
//                     const SizedBox(height: 6),
//                     const Text(
//                       'This key will never be shown again. Store it safely.',
//                       style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
//                     ),
//                     const SizedBox(height: 12),
//                     CopyField(value: _newRawKey!, label: 'API Key'),
//                     const SizedBox(height: 10),
//                     Align(
//                       alignment: Alignment.centerRight,
//                       child: TextButton(
//                         onPressed: () => setState(() => _newRawKey = null),
//                         child: const Text('I\'ve saved it', style: TextStyle(color: AppColors.textSecondary)),
//                       ),
//                     ),
//                   ],
//                 ),
//               ).animate().shake(duration: 400.ms),

//             // Info box
//             Container(
//               padding: const EdgeInsets.all(16),
//               margin: const EdgeInsets.only(bottom: 20),
//               decoration: BoxDecoration(
//                 color: AppColors.goldGlow,
//                 borderRadius: BorderRadius.circular(10),
//                 border: Border.all(color: AppColors.accent.withValues(alpha: 0.2)),
//               ),
//               child: const Row(
//                 children: [
//                   Icon(Icons.info_outline_rounded, color: AppColors.accent, size: 16),
//                   SizedBox(width: 10),
//                   Expanded(
//                     child: Text(
//                       'Use these keys in your apps to call the StreamAI API. '
//                       'Never share them publicly. Keys authenticate to our platform.',
//                       style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
//                     ),
//                   ),
//                 ],
//               ),
//             ),

//             // Keys list
//             _loading
//                 ? const Center(child: CircularProgressIndicator(color: AppColors.accent, strokeWidth: 2))
//                 : _keys.isEmpty
//                     ? EmptyState(
//                         icon: Icons.vpn_key_rounded,
//                         title: 'No API keys yet',
//                         subtitle: 'Create your first key to start using the API',
//                         action: PrimaryButton(
//                           label: 'Create First Key',
//                           icon: Icons.add_rounded,
//                           onPressed: _createKey,
//                         ),
//                       )
//                     : Column(
//                         children: _keys.asMap().entries.map((e) {
//                           final key = e.value;
//                           return _KeyCard(
//                             key: ValueKey(key.id),
//                             apiKey: key,
//                             onRevoke: () => _revokeKey(key),
//                           ).animate().fadeIn(delay: Duration(milliseconds: e.key * 60));
//                         }).toList(),
//                       ),
//           ],
//         ),
//       ),
//     );
//   }
// }

// class _KeyCard extends StatelessWidget {
//   final ApiKeyModel apiKey;
//   final VoidCallback onRevoke;

//   const _KeyCard({super.key, required this.apiKey, required this.onRevoke});

//   @override
//   Widget build(BuildContext context) {
//     return Container(
//       margin: const EdgeInsets.only(bottom: 12),
//       padding: const EdgeInsets.all(18),
//       decoration: BoxDecoration(
//         color: AppColors.bgCard,
//         borderRadius: BorderRadius.circular(12),
//         border: Border.all(color: AppColors.border),
//       ),
//       child: Row(
//         children: [
//           Container(
//             padding: const EdgeInsets.all(8),
//             decoration: BoxDecoration(
//               color: AppColors.goldGlow,
//               borderRadius: BorderRadius.circular(8),
//             ),
//             child: const Icon(Icons.vpn_key_rounded, color: AppColors.accent, size: 18),
//           ),
//           const SizedBox(width: 14),
//           Expanded(
//             child: Column(
//               crossAxisAlignment: CrossAxisAlignment.start,
//               children: [
//                 Text(apiKey.name, style: const TextStyle(color: AppColors.textPrimary, fontSize: 14, fontWeight: FontWeight.w600)),
//                 const SizedBox(height: 4),
//                 Row(
//                   children: [
//                     Text(
//                       '${apiKey.prefix}••••••••••••••••',
//                       style: const TextStyle(
//                         fontFamily: 'JetBrains Mono',
//                         color: AppColors.textMuted,
//                         fontSize: 12,
//                       ),
//                     ),
//                     const SizedBox(width: 12),
//                     Text(
//                       'Created ${_formatDate(apiKey.createdAt)}',
//                       style: const TextStyle(color: AppColors.textMuted, fontSize: 11),
//                     ),
//                   ],
//                 ),
//                 if (apiKey.lastUsedAt != null)
//                   Text(
//                     'Last used ${_formatDate(apiKey.lastUsedAt!)}',
//                     style: const TextStyle(color: AppColors.textMuted, fontSize: 11),
//                   ),
//               ],
//             ),
//           ),
//           TextButton.icon(
//             onPressed: onRevoke,
//             icon: const Icon(Icons.delete_outline_rounded, size: 15, color: AppColors.danger),
//             label: const Text('Revoke', style: TextStyle(color: AppColors.danger, fontSize: 13)),
//           ),
//         ],
//       ),
//     );
//   }

//   String _formatDate(String iso) {
//     try {
//       final dt = DateTime.parse(iso);
//       return '${dt.day}/${dt.month}/${dt.year}';
//     } catch (_) {
//       return iso;
//     }
//   }
// }

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../models/api_key.dart';
import '../../services/api_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/shared_widgets.dart';

class ApiKeysScreen extends StatefulWidget {
  const ApiKeysScreen({super.key});

  @override
  State<ApiKeysScreen> createState() => _ApiKeysScreenState();
}

class _ApiKeysScreenState extends State<ApiKeysScreen> {
  List<ApiKeyModel> _keys = [];
  bool _loading = true;
  String? _newRawKey; // Shown once after creation

  @override
  void initState() {
    super.initState();
    _loadKeys();
  }

  Future<void> _loadKeys() async {
    setState(() => _loading = true);
    try {
      final data = await ApiService.instance.getApiKeys();
      setState(() {
        _keys = data
            .map((j) => ApiKeyModel.fromJson(j as Map<String, dynamic>))
            .toList();
        _loading = false;
      });
    } catch (_) {
      setState(() => _loading = false);
    }
  }

  Future<void> _createKey() async {
    final nameCtrl = TextEditingController(text: 'My Key');
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.bgCard,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: AppColors.border),
        ),
        title: Text('Create API Key',
            style: TextStyle(color: AppColors.textPrimary)),
        content: SizedBox(
          width: 360,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Give your key a name to identify it later.',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(labelText: 'Key name'),
                autofocus: true,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Create'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    final result = await ApiService.instance.createApiKey(nameCtrl.text.trim());
    if (result['key'] != null) {
      setState(() => _newRawKey = result['key'] as String);
      await _loadKeys();
    }
  }

  Future<void> _revokeKey(ApiKeyModel key) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.bgCard,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: AppColors.border),
        ),
        title: Text('Revoke Key',
            style: TextStyle(color: AppColors.textPrimary)),
        content: Text(
          'Revoke "${key.name}"?\nThis key will stop working immediately.',
          style: TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Revoke'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    final ok = await ApiService.instance.revokeApiKey(key.id);
    if (ok) _loadKeys();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SectionHeader(
              title: 'API Keys',
              subtitle: 'Manage keys for accessing the streaming API',
              action: PrimaryButton(
                label: 'New Key',
                icon: Icons.add_rounded,
                onPressed: _createKey,
              ),
            ).animate().fadeIn(),

            const SizedBox(height: 24),

            // New key reveal banner
            if (_newRawKey != null)
              Container(
                padding: const EdgeInsets.all(20),
                margin: const EdgeInsets.only(bottom: 20),
                decoration: BoxDecoration(
                  color: AppColors.success.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color: AppColors.success.withValues(alpha: 0.3)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.check_circle_rounded,
                            color: AppColors.success, size: 18),
                        SizedBox(width: 8),
                        Text(
                          'Key created — copy it now!',
                          style: TextStyle(
                              color: AppColors.success,
                              fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'This key will never be shown again. Store it safely.',
                      style: TextStyle(
                          color: AppColors.textSecondary, fontSize: 12),
                    ),
                    const SizedBox(height: 12),
                    CopyField(value: _newRawKey!, label: 'API Key'),
                    const SizedBox(height: 10),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: () => setState(() => _newRawKey = null),
                        child: Text('I\'ve saved it',
                            style: TextStyle(color: AppColors.textSecondary)),
                      ),
                    ),
                  ],
                ),
              ).animate().shake(duration: 400.ms),

            // Info box
            Container(
              padding: const EdgeInsets.all(16),
              margin: const EdgeInsets.only(bottom: 20),
              decoration: BoxDecoration(
                color: AppColors.goldGlow,
                borderRadius: BorderRadius.circular(10),
                border:
                    Border.all(color: AppColors.accent.withValues(alpha: 0.2)),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline_rounded,
                      color: AppColors.accent, size: 16),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Use these keys in your apps to call the RealFaceAI API. '
                      'Never share them publicly. Keys authenticate to our platform.',
                      style: TextStyle(
                          color: AppColors.textSecondary, fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),

            // Keys list
            _loading
                ? Center(
                    child: CircularProgressIndicator(
                        color: AppColors.accent, strokeWidth: 2))
                : _keys.isEmpty
                    ? EmptyState(
                        icon: Icons.vpn_key_rounded,
                        title: 'No API keys yet',
                        subtitle:
                            'Create your first key to start using the API',
                        action: PrimaryButton(
                          label: 'Create First Key',
                          icon: Icons.add_rounded,
                          onPressed: _createKey,
                        ),
                      )
                    : Column(
                        children: _keys.asMap().entries.map((e) {
                          final key = e.value;
                          return _KeyCard(
                            key: ValueKey(key.id),
                            apiKey: key,
                            onRevoke: () => _revokeKey(key),
                          ).animate().fadeIn(
                              delay: Duration(milliseconds: e.key * 60));
                        }).toList(),
                      ),
          ],
        ),
      ),
    );
  }
}

class _KeyCard extends StatelessWidget {
  final ApiKeyModel apiKey;
  final VoidCallback onRevoke;

  const _KeyCard({super.key, required this.apiKey, required this.onRevoke});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppColors.goldGlow,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(Icons.vpn_key_rounded,
                color: AppColors.accent, size: 18),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(apiKey.name,
                    style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Text(
                      '${apiKey.prefix}••••••••••••••••',
                      style: TextStyle(
                        fontFamily: 'JetBrains Mono',
                        color: AppColors.textMuted,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      'Created ${_formatDate(apiKey.createdAt)}',
                      style: TextStyle(
                          color: AppColors.textMuted, fontSize: 11),
                    ),
                  ],
                ),
                if (apiKey.lastUsedAt != null)
                  Text(
                    'Last used ${_formatDate(apiKey.lastUsedAt!)}',
                    style: TextStyle(
                        color: AppColors.textMuted, fontSize: 11),
                  ),
              ],
            ),
          ),
          TextButton.icon(
            onPressed: onRevoke,
            icon: Icon(Icons.delete_outline_rounded,
                size: 15, color: AppColors.danger),
            label: Text('Revoke',
                style: TextStyle(color: AppColors.danger, fontSize: 13)),
          ),
        ],
      ),
    );
  }

  String _formatDate(String iso) {
    try {
      final dt = DateTime.parse(iso);
      return '${dt.day}/${dt.month}/${dt.year}';
    } catch (_) {
      return iso;
    }
  }
}
