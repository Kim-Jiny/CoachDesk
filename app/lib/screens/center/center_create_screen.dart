import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import '../../providers/auth_provider.dart';

class CenterCreateScreen extends ConsumerStatefulWidget {
  const CenterCreateScreen({super.key});

  @override
  ConsumerState<CenterCreateScreen> createState() => _CenterCreateScreenState();
}

class _CenterCreateScreenState extends ConsumerState<CenterCreateScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _descController = TextEditingController();

  @override
  void dispose() {
    _nameController.dispose();
    _descController.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    if (!_formKey.currentState!.validate()) return;

    await ref.read(authProvider.notifier).createCenter(
      name: _nameController.text.trim(),
      description: _descController.text.trim().isEmpty
          ? null
          : _descController.text.trim(),
    );
    // Router redirect automatically navigates to /home when selectedCenter is set
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('새 센터 만들기'),
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
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: AppTheme.primaryColor.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  children: [
                    Icon(
                      Icons.add_business_rounded,
                      size: 48,
                      color: AppTheme.primaryColor.withValues(alpha: 0.7),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      '센터를 만들면 회원을 관리하고\n수업 일정을 운영할 수 있습니다',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 14, color: Colors.grey),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: '센터 이름',
                  prefixIcon: Icon(Icons.business_outlined),
                  hintText: '예: OO 필라테스',
                ),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? '센터 이름을 입력하세요' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _descController,
                decoration: const InputDecoration(
                  labelText: '센터 설명 (선택)',
                  prefixIcon: Icon(Icons.description_outlined),
                  hintText: '간단한 소개를 입력하세요',
                ),
                maxLines: 2,
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
                    style: const TextStyle(
                        color: AppTheme.errorColor, fontSize: 13),
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
                  onPressed: authState.isLoading ? null : _create,
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
                      : const Text('센터 만들기',
                          style: TextStyle(fontSize: 16)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
