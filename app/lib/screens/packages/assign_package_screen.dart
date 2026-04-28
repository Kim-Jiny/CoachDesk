import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../models/package.dart';
import '../../providers/package_provider.dart';
import '../../widgets/common.dart';

class AssignPackageScreen extends ConsumerStatefulWidget {
  final String memberId;
  final String memberName;
  const AssignPackageScreen({
    super.key,
    required this.memberId,
    required this.memberName,
  });

  @override
  ConsumerState<AssignPackageScreen> createState() =>
      _AssignPackageScreenState();
}

class _AssignPackageScreenState extends ConsumerState<AssignPackageScreen> {
  Package? _selectedPackage;
  final _paidAmountController = TextEditingController();
  String _paymentMethod = 'CASH';
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    Future.microtask(() => ref.read(packageProvider.notifier).fetchPackages());
  }

  @override
  void dispose() {
    _paidAmountController.dispose();
    super.dispose();
  }

  Future<void> _assign() async {
    if (_selectedPackage == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('패키지를 선택하세요')));
      return;
    }

    setState(() => _isSubmitting = true);

    final success = await ref
        .read(packageProvider.notifier)
        .assignToMember(
          memberId: widget.memberId,
          packageId: _selectedPackage!.id,
          paidAmount:
              int.tryParse(_paidAmountController.text) ??
              _selectedPackage!.price,
          paymentMethod: _paymentMethod,
        );

    setState(() => _isSubmitting = false);

    if (success && mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('패키지가 할당되었습니다')));
      context.pop(true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final pkgState = ref.watch(packageProvider);
    final activePackages = pkgState.packages.where((p) => p.isActive).toList();
    final formatter = NumberFormat('#,###');

    return DismissKeyboardOnTap(child: Scaffold(
      appBar: AppBar(title: Text('${widget.memberName} 패키지 할당')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DropdownButtonFormField<Package>(
              decoration: const InputDecoration(
                labelText: '패키지 선택 *',
                prefixIcon: Icon(Icons.inventory_2_outlined),
              ),
              items: activePackages.map((p) {
                return DropdownMenuItem(
                  value: p,
                  child: Text(
                    '[${p.isAdminScoped ? '관리자' : '센터'}] ${p.name} '
                    '(${p.totalSessions}회 / ${formatter.format(p.price)}원)',
                  ),
                );
              }).toList(),
              onChanged: (v) {
                setState(() {
                  _selectedPackage = v;
                  if (v != null) {
                    _paidAmountController.text = v.price.toString();
                  }
                });
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _paidAmountController,
              decoration: const InputDecoration(
                labelText: '결제 금액',
                prefixIcon: Icon(Icons.payments_outlined),
                suffixText: '원',
              ),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              initialValue: _paymentMethod,
              decoration: const InputDecoration(
                labelText: '결제 수단',
                prefixIcon: Icon(Icons.credit_card_outlined),
              ),
              items: const [
                DropdownMenuItem(value: 'CASH', child: Text('현금')),
                DropdownMenuItem(value: 'CARD', child: Text('카드')),
                DropdownMenuItem(value: 'TRANSFER', child: Text('계좌이체')),
              ],
              onChanged: (v) => setState(() => _paymentMethod = v ?? 'CASH'),
            ),
            if (_selectedPackage != null) ...[
              const SizedBox(height: 24),
              Card(
                color: Theme.of(
                  context,
                ).colorScheme.primary.withValues(alpha: 0.05),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '패키지 요약',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '${_selectedPackage!.name} - ${_selectedPackage!.totalSessions}회',
                      ),
                      Text('구분: ${_selectedPackage!.scopeLabel}'),
                      if (_selectedPackage!.validDays != null)
                        Text('유효기간: ${_selectedPackage!.validDays}일'),
                      Text('정가: ${formatter.format(_selectedPackage!.price)}원'),
                    ],
                  ),
                ),
              ),
            ],
            const SizedBox(height: 32),
            ElevatedButton(
              onPressed: _isSubmitting ? null : _assign,
              child: _isSubmitting
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('패키지 할당'),
            ),
          ],
        ),
      ),
    ));
  }
}
