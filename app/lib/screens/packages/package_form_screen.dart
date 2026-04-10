import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../models/package.dart';
import '../../providers/package_provider.dart';

class PackageFormScreen extends ConsumerStatefulWidget {
  final Package? package;
  const PackageFormScreen({super.key, this.package});

  @override
  ConsumerState<PackageFormScreen> createState() => _PackageFormScreenState();
}

class _PackageFormScreenState extends ConsumerState<PackageFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _sessionsController;
  late final TextEditingController _priceController;
  late final TextEditingController _validDaysController;
  late bool _isActive;
  late bool _isPublic;

  bool get isEditing => widget.package != null;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.package?.name ?? '');
    _sessionsController = TextEditingController(
      text: widget.package?.totalSessions.toString() ?? '',
    );
    _priceController = TextEditingController(
      text: widget.package?.price.toString() ?? '',
    );
    _validDaysController = TextEditingController(
      text: widget.package?.validDays?.toString() ?? '',
    );
    _isActive = widget.package?.isActive ?? true;
    _isPublic = widget.package?.isPublic ?? false;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _sessionsController.dispose();
    _priceController.dispose();
    _validDaysController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    final data = {
      'name': _nameController.text.trim(),
      'totalSessions': int.parse(_sessionsController.text.trim()),
      'price': int.parse(_priceController.text.trim()),
      'isActive': _isActive,
      'isPublic': _isPublic,
      if (_validDaysController.text.trim().isNotEmpty)
        'validDays': int.parse(_validDaysController.text.trim()),
    };

    final notifier = ref.read(packageProvider.notifier);
    final success = isEditing
        ? await notifier.updatePackage(widget.package!.id, data)
        : await notifier.createPackage(data);

    if (success && mounted) context.pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(isEditing ? '패키지 수정' : '패키지 등록')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: '패키지 이름 *',
                  prefixIcon: Icon(Icons.label_outline),
                  hintText: '예: PT 10회',
                ),
                validator: (v) => (v == null || v.isEmpty) ? '이름을 입력하세요' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _sessionsController,
                decoration: const InputDecoration(
                  labelText: '총 세션 수 *',
                  prefixIcon: Icon(Icons.repeat),
                  suffixText: '회',
                ),
                keyboardType: TextInputType.number,
                validator: (v) {
                  if (v == null || v.isEmpty) return '세션 수를 입력하세요';
                  if (int.tryParse(v) == null || int.parse(v) < 1) {
                    return '1 이상 입력하세요';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _priceController,
                decoration: const InputDecoration(
                  labelText: '가격 *',
                  prefixIcon: Icon(Icons.payments_outlined),
                  suffixText: '원',
                ),
                keyboardType: TextInputType.number,
                validator: (v) {
                  if (v == null || v.isEmpty) return '가격을 입력하세요';
                  if (int.tryParse(v) == null) return '숫자를 입력하세요';
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _validDaysController,
                decoration: const InputDecoration(
                  labelText: '유효 기간 (선택)',
                  prefixIcon: Icon(Icons.timer_outlined),
                  suffixText: '일',
                  hintText: '미입력 시 무제한',
                ),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: Column(
                  children: [
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('활성 상태'),
                      subtitle: Text(
                        _isActive ? '현재 사용 가능한 패키지로 노출됩니다' : '비활성 상태로 보관됩니다',
                      ),
                      value: _isActive,
                      onChanged: (value) => setState(() => _isActive = value),
                    ),
                    const Divider(),
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('공개 여부'),
                      subtitle: Text(
                        _isPublic ? '공개 패키지로 운영합니다' : '비공개 패키지로 내부 관리용입니다',
                      ),
                      value: _isPublic,
                      onChanged: (value) => setState(() => _isPublic = value),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 32),
              ElevatedButton(
                onPressed: _save,
                child: Text(isEditing ? '수정' : '등록'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
