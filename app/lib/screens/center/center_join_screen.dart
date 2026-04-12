import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import '../../providers/auth_provider.dart';
import '../../models/organization.dart';

class CenterJoinScreen extends ConsumerStatefulWidget {
  const CenterJoinScreen({super.key});

  @override
  ConsumerState<CenterJoinScreen> createState() => _CenterJoinScreenState();
}

class _CenterJoinScreenState extends ConsumerState<CenterJoinScreen> {
  final _formKey = GlobalKey<FormState>();
  final _codeController = TextEditingController();
  CenterJoinRequest? _sentRequest;

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    final request = await ref.read(authProvider.notifier).requestJoinCenter(
      _codeController.text.trim(),
    );

    if (request != null && mounted) {
      setState(() => _sentRequest = request);
    }
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('센터 합류'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            final centers = ref.read(authProvider).centers;
            context.go(centers.isNotEmpty ? '/centers' : '/onboarding');
          },
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: _sentRequest != null
            ? _buildSuccessView()
            : _buildFormView(authState),
      ),
    );
  }

  Widget _buildSuccessView() {
    return Column(
      children: [
        const SizedBox(height: 48),
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: AppTheme.successColor.withValues(alpha: 0.1),
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.check_circle_outline,
            size: 64,
            color: AppTheme.successColor,
          ),
        ),
        const SizedBox(height: 24),
        const Text(
          '합류 신청 완료',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Text(
          '${_sentRequest!.organizationName}에 합류 신청을 보냈습니다.\n센터 관리자가 승인하면 합류됩니다.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
        ),
        const SizedBox(height: 32),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton(
            onPressed: () {
              setState(() => _sentRequest = null);
              _codeController.clear();
            },
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('다른 센터 코드 입력'),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: TextButton(
            onPressed: () {
              final centers = ref.read(authProvider).centers;
              context.go(centers.isNotEmpty ? '/centers' : '/onboarding');
            },
            child: const Text('돌아가기'),
          ),
        ),
      ],
    );
  }

  Widget _buildFormView(AuthState authState) {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppTheme.secondaryColor.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              children: [
                Icon(
                  Icons.group_add_rounded,
                  size: 48,
                  color: AppTheme.secondaryColor.withValues(alpha: 0.7),
                ),
                const SizedBox(height: 12),
                const Text(
                  '센터 관리자에게 받은\n초대 코드를 입력하세요',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 14, color: Colors.grey),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          TextFormField(
            controller: _codeController,
            decoration: const InputDecoration(
              labelText: '센터 코드',
              prefixIcon: Icon(Icons.vpn_key_outlined),
              hintText: '6자리 코드 입력',
            ),
            textCapitalization: TextCapitalization.characters,
            validator: (v) =>
                (v == null || v.trim().isEmpty) ? '센터 코드를 입력하세요' : null,
          ),
          if (authState.error != null) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.errorColor.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                authState.error!,
                style:
                    const TextStyle(color: AppTheme.errorColor, fontSize: 13),
                textAlign: TextAlign.center,
              ),
            ),
          ],
          const SizedBox(height: 32),
          Container(
            decoration: BoxDecoration(
              gradient:
                  authState.isLoading ? null : AppTheme.primaryGradient,
              color: authState.isLoading ? Colors.grey.shade300 : null,
              borderRadius: BorderRadius.circular(12),
            ),
            child: ElevatedButton(
              onPressed: authState.isLoading ? null : _submit,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.transparent,
                shadowColor: Colors.transparent,
                disabledBackgroundColor: Colors.transparent,
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              child: authState.isLoading
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Text('합류 신청', style: TextStyle(fontSize: 16)),
            ),
          ),
        ],
      ),
    );
  }
}
