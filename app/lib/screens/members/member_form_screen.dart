import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../providers/member_provider.dart';

class MemberFormScreen extends ConsumerStatefulWidget {
  final Map<String, dynamic>? member;

  const MemberFormScreen({super.key, this.member});

  @override
  ConsumerState<MemberFormScreen> createState() => _MemberFormScreenState();
}

class _MemberFormScreenState extends ConsumerState<MemberFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _phoneController;
  late final TextEditingController _emailController;
  late final TextEditingController _quickMemoController;
  late final TextEditingController _memoController;
  String? _gender;

  bool get isEditing => widget.member != null;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(
      text: widget.member?['name'] as String? ?? '',
    );
    _phoneController = TextEditingController(
      text: widget.member?['phone'] as String? ?? '',
    );
    _emailController = TextEditingController(
      text: widget.member?['email'] as String? ?? '',
    );
    _quickMemoController = TextEditingController(
      text: widget.member?['quickMemo'] as String? ?? '',
    );
    _memoController = TextEditingController(
      text: widget.member?['memo'] as String? ?? '',
    );
    _gender = widget.member?['gender'] as String?;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _quickMemoController.dispose();
    _memoController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    final data = {
      'name': _nameController.text.trim(),
      if (_phoneController.text.trim().isNotEmpty)
        'phone': _phoneController.text.trim(),
      if (_emailController.text.trim().isNotEmpty)
        'email': _emailController.text.trim(),
      if (_quickMemoController.text.trim().isNotEmpty)
        'quickMemo': _quickMemoController.text.trim(),
      if (_memoController.text.trim().isNotEmpty)
        'memo': _memoController.text.trim(),
      if (_gender != null) 'gender': _gender,
    };

    final notifier = ref.read(memberProvider.notifier);
    final success = isEditing
        ? await notifier.updateMember(widget.member!['id'] as String, data)
        : await notifier.createMember(data);

    if (success && mounted) {
      context.pop(true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(isEditing ? '회원 수정' : '회원 등록')),
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => FocusScope.of(context).unfocus(),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  controller: _nameController,
                  decoration: const InputDecoration(
                    labelText: '이름 *',
                    prefixIcon: Icon(Icons.person_outline),
                  ),
                  validator: (v) =>
                      (v == null || v.isEmpty) ? '이름을 입력하세요' : null,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _phoneController,
                  decoration: const InputDecoration(
                    labelText: '전화번호',
                    prefixIcon: Icon(Icons.phone_outlined),
                  ),
                  keyboardType: TextInputType.phone,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _emailController,
                  decoration: const InputDecoration(
                    labelText: '이메일',
                    prefixIcon: Icon(Icons.email_outlined),
                  ),
                  keyboardType: TextInputType.emailAddress,
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  initialValue: _gender,
                  decoration: const InputDecoration(
                    labelText: '성별',
                    prefixIcon: Icon(Icons.wc_outlined),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'MALE', child: Text('남성')),
                    DropdownMenuItem(value: 'FEMALE', child: Text('여성')),
                    DropdownMenuItem(value: 'OTHER', child: Text('기타')),
                  ],
                  onChanged: (v) => setState(() => _gender = v),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _quickMemoController,
                  decoration: const InputDecoration(
                    labelText: '목록 메모',
                    helperText: '회원 리스트에서 바로 보이는 짧은 메모',
                    prefixIcon: Icon(Icons.short_text_rounded),
                  ),
                  maxLines: 2,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _memoController,
                  decoration: const InputDecoration(
                    labelText: '상세 메모',
                    helperText: '회원 상세에서 확인하는 메모',
                    prefixIcon: Icon(Icons.note_outlined),
                    alignLabelWithHint: true,
                  ),
                  maxLines: 3,
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
      ),
    );
  }
}
