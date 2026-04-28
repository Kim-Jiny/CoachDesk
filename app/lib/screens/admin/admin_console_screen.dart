import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/api_client.dart';
import '../../core/theme.dart';
import '../../providers/auth_provider.dart';
import '../../widgets/common.dart';

class AdminConsoleScreen extends ConsumerStatefulWidget {
  const AdminConsoleScreen({super.key});

  @override
  ConsumerState<AdminConsoleScreen> createState() => _AdminConsoleScreenState();
}

class _AdminConsoleScreenState extends ConsumerState<AdminConsoleScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  final _orgSearchController = TextEditingController();
  final _userSearchController = TextEditingController();
  final _accountSearchController = TextEditingController();

  final _orgNameController = TextEditingController();
  final _orgDescriptionController = TextEditingController();
  final _orgMaxAdminController = TextEditingController();
  final _orgMaxMemberController = TextEditingController();
  final _orgOpenDaysController = TextEditingController();
  final _orgOpenHoursController = TextEditingController();
  final _orgCancelDeadlineController = TextEditingController();

  final _userNameController = TextEditingController();
  final _userEmailController = TextEditingController();
  final _userPhoneController = TextEditingController();
  final _userOpenDaysController = TextEditingController();
  final _userOpenHoursController = TextEditingController();
  final _userCancelDeadlineController = TextEditingController();

  final _accountNameController = TextEditingController();
  final _accountEmailController = TextEditingController();

  _AdminDashboardStats? _dashboard;
  _AdminReportOverview? _reportOverview;
  List<_AdminOrganizationRecord> _organizations = const [];
  List<_AdminUserRecord> _users = const [];
  List<_AdminMemberAccountRecord> _memberAccounts = const [];

  _AdminOrganizationRecord? _selectedOrganization;
  _AdminUserRecord? _selectedUser;
  _AdminMemberAccountRecord? _selectedMemberAccount;

  bool _loadingDashboard = true;
  bool _loadingReports = true;
  bool _loadingOrganizations = true;
  bool _loadingUsers = true;
  bool _loadingMemberAccounts = true;

  bool _savingOrganization = false;
  bool _savingUser = false;
  bool _savingMemberAccount = false;

  String? _dashboardError;
  String? _reportError;
  String? _orgError;
  String? _userError;
  String? _memberAccountError;

  String _orgPlanType = 'FREE';
  String _orgBookingMode = 'PRIVATE';
  String _orgReservationPolicy = 'AUTO_CONFIRM';
  String _userBookingMode = 'PRIVATE';
  String _userReservationPolicy = 'AUTO_CONFIRM';

  Dio get _dio => ref.read(dioProvider);

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _loadAll();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _orgSearchController.dispose();
    _userSearchController.dispose();
    _accountSearchController.dispose();
    _orgNameController.dispose();
    _orgDescriptionController.dispose();
    _orgMaxAdminController.dispose();
    _orgMaxMemberController.dispose();
    _orgOpenDaysController.dispose();
    _orgOpenHoursController.dispose();
    _orgCancelDeadlineController.dispose();
    _userNameController.dispose();
    _userEmailController.dispose();
    _userPhoneController.dispose();
    _userOpenDaysController.dispose();
    _userOpenHoursController.dispose();
    _userCancelDeadlineController.dispose();
    _accountNameController.dispose();
    _accountEmailController.dispose();
    super.dispose();
  }

  Future<void> _loadAll() async {
    await Future.wait([
      _loadDashboard(),
      _loadReports(),
      _loadOrganizations(),
      _loadUsers(),
      _loadMemberAccounts(),
    ]);
  }

  Future<void> _loadDashboard() async {
    setState(() {
      _loadingDashboard = true;
      _dashboardError = null;
    });
    try {
      final response = await _dio.get('/admin/dashboard');
      if (!mounted) return;
      setState(() {
        _dashboard = _AdminDashboardStats.fromJson(
          response.data as Map<String, dynamic>,
        );
        _loadingDashboard = false;
      });
    } on DioException catch (e) {
      if (!mounted) return;
      setState(() {
        _dashboardError =
            e.response?.data?['error'] as String? ?? '대시보드를 불러오지 못했습니다';
        _loadingDashboard = false;
      });
    }
  }

  Future<void> _loadReports() async {
    setState(() {
      _loadingReports = true;
      _reportError = null;
    });
    try {
      final response = await _dio.get('/admin/reports/overview');
      if (!mounted) return;
      setState(() {
        _reportOverview = _AdminReportOverview.fromJson(
          response.data as Map<String, dynamic>,
        );
        _loadingReports = false;
      });
    } on DioException catch (e) {
      if (!mounted) return;
      setState(() {
        _reportError =
            e.response?.data?['error'] as String? ?? '리포트를 불러오지 못했습니다';
        _loadingReports = false;
      });
    }
  }

  Future<void> _loadOrganizations({String? selectedId}) async {
    setState(() {
      _loadingOrganizations = true;
      _orgError = null;
    });
    try {
      final response = await _dio.get(
        '/admin/organizations',
        queryParameters: {
          if (_orgSearchController.text.trim().isNotEmpty)
            'search': _orgSearchController.text.trim(),
        },
      );
      final organizations =
          ((response.data as Map<String, dynamic>)['organizations'] as List? ??
                  const [])
              .map(
                (item) => _AdminOrganizationRecord.fromJson(
                  item as Map<String, dynamic>,
                ),
              )
              .toList();

      final nextSelection = _resolveSelectedRecord<_AdminOrganizationRecord>(
        items: organizations,
        selectedId: selectedId ?? _selectedOrganization?.id,
        getId: (item) => item.id,
      );

      if (!mounted) return;
      setState(() {
        _organizations = organizations;
        _selectedOrganization = nextSelection;
        _loadingOrganizations = false;
      });

      if (nextSelection != null) {
        await _loadOrganizationDetail(nextSelection.id);
      } else {
        _clearOrganizationForm();
      }
    } on DioException catch (e) {
      if (!mounted) return;
      setState(() {
        _orgError =
            e.response?.data?['error'] as String? ?? '센터 목록을 불러오지 못했습니다';
        _loadingOrganizations = false;
      });
    }
  }

  Future<void> _loadUsers({String? selectedId}) async {
    setState(() {
      _loadingUsers = true;
      _userError = null;
    });
    try {
      final response = await _dio.get(
        '/admin/users',
        queryParameters: {
          if (_userSearchController.text.trim().isNotEmpty)
            'search': _userSearchController.text.trim(),
        },
      );
      final users =
          ((response.data as Map<String, dynamic>)['users'] as List? ??
                  const [])
              .map(
                (item) =>
                    _AdminUserRecord.fromJson(item as Map<String, dynamic>),
              )
              .toList();

      final nextSelection = _resolveSelectedRecord<_AdminUserRecord>(
        items: users,
        selectedId: selectedId ?? _selectedUser?.id,
        getId: (item) => item.id,
      );

      if (!mounted) return;
      setState(() {
        _users = users;
        _selectedUser = nextSelection;
        _loadingUsers = false;
      });

      if (nextSelection != null) {
        await _loadUserDetail(nextSelection.id);
      } else {
        _clearUserForm();
      }
    } on DioException catch (e) {
      if (!mounted) return;
      setState(() {
        _userError =
            e.response?.data?['error'] as String? ?? '유저 목록을 불러오지 못했습니다';
        _loadingUsers = false;
      });
    }
  }

  Future<void> _loadMemberAccounts({String? selectedId}) async {
    setState(() {
      _loadingMemberAccounts = true;
      _memberAccountError = null;
    });
    try {
      final response = await _dio.get(
        '/admin/member-accounts',
        queryParameters: {
          if (_accountSearchController.text.trim().isNotEmpty)
            'search': _accountSearchController.text.trim(),
        },
      );
      final accounts =
          ((response.data as Map<String, dynamic>)['memberAccounts'] as List? ??
                  const [])
              .map(
                (item) => _AdminMemberAccountRecord.fromJson(
                  item as Map<String, dynamic>,
                ),
              )
              .toList();

      final nextSelection = _resolveSelectedRecord<_AdminMemberAccountRecord>(
        items: accounts,
        selectedId: selectedId ?? _selectedMemberAccount?.id,
        getId: (item) => item.id,
      );

      if (!mounted) return;
      setState(() {
        _memberAccounts = accounts;
        _selectedMemberAccount = nextSelection;
        _loadingMemberAccounts = false;
      });

      if (nextSelection != null) {
        await _loadMemberAccountDetail(nextSelection.id);
      } else {
        _clearMemberAccountForm();
      }
    } on DioException catch (e) {
      if (!mounted) return;
      setState(() {
        _memberAccountError =
            e.response?.data?['error'] as String? ?? '회원 계정 목록을 불러오지 못했습니다';
        _loadingMemberAccounts = false;
      });
    }
  }

  Future<void> _loadOrganizationDetail(String id) async {
    try {
      final responses = await Future.wait([
        _dio.get('/admin/organizations/$id'),
        _dio.get('/admin/organizations/$id/join-requests'),
      ]);
      final detail =
          _AdminOrganizationRecord.fromJson(
            responses[0].data as Map<String, dynamic>,
          ).copyWith(
            joinRequests:
                ((responses[1].data as Map<String, dynamic>)['requests']
                            as List? ??
                        const [])
                    .map(
                      (item) => _AdminJoinRequest.fromJson(
                        item as Map<String, dynamic>,
                      ),
                    )
                    .toList(),
          );
      if (!mounted) return;
      setState(() => _selectedOrganization = detail);
      _bindOrganizationForm(detail);
    } on DioException catch (e) {
      _showError(e.response?.data?['error'] as String? ?? '센터 상세를 불러오지 못했습니다');
    }
  }

  Future<void> _loadUserDetail(String id) async {
    try {
      final response = await _dio.get('/admin/users/$id');
      final detail = _AdminUserRecord.fromJson(
        response.data as Map<String, dynamic>,
      );
      if (!mounted) return;
      setState(() => _selectedUser = detail);
      _bindUserForm(detail);
    } on DioException catch (e) {
      _showError(e.response?.data?['error'] as String? ?? '유저 상세를 불러오지 못했습니다');
    }
  }

  Future<void> _loadMemberAccountDetail(String id) async {
    try {
      final response = await _dio.get('/admin/member-accounts/$id');
      final detail = _AdminMemberAccountRecord.fromJson(
        response.data as Map<String, dynamic>,
      );
      if (!mounted) return;
      setState(() => _selectedMemberAccount = detail);
      _bindMemberAccountForm(detail);
    } on DioException catch (e) {
      _showError(
        e.response?.data?['error'] as String? ?? '회원 계정 상세를 불러오지 못했습니다',
      );
    }
  }

  void _bindOrganizationForm(_AdminOrganizationRecord org) {
    _orgNameController.text = org.name;
    _orgDescriptionController.text = org.description ?? '';
    _orgMaxAdminController.text = '${org.maxAdminCount}';
    _orgMaxMemberController.text = '${org.maxMemberCount}';
    _orgOpenDaysController.text = '${org.reservationOpenDaysBefore}';
    _orgOpenHoursController.text = '${org.reservationOpenHoursBefore}';
    _orgCancelDeadlineController.text =
        '${org.reservationCancelDeadlineMinutes}';
    _orgPlanType = org.planType;
    _orgBookingMode = org.bookingMode;
    _orgReservationPolicy = org.reservationPolicy;
  }

  void _bindUserForm(_AdminUserRecord user) {
    _userNameController.text = user.name;
    _userEmailController.text = user.email;
    _userPhoneController.text = user.phone ?? '';
    _userOpenDaysController.text = '${user.reservationOpenDaysBefore}';
    _userOpenHoursController.text = '${user.reservationOpenHoursBefore}';
    _userCancelDeadlineController.text =
        '${user.reservationCancelDeadlineMinutes}';
    _userBookingMode = user.bookingMode;
    _userReservationPolicy = user.reservationPolicy;
  }

  void _bindMemberAccountForm(_AdminMemberAccountRecord account) {
    _accountNameController.text = account.name;
    _accountEmailController.text = account.email;
  }

  void _clearOrganizationForm() {
    _orgNameController.clear();
    _orgDescriptionController.clear();
    _orgMaxAdminController.clear();
    _orgMaxMemberController.clear();
    _orgOpenDaysController.clear();
    _orgOpenHoursController.clear();
    _orgCancelDeadlineController.clear();
    _orgPlanType = 'FREE';
    _orgBookingMode = 'PRIVATE';
    _orgReservationPolicy = 'AUTO_CONFIRM';
  }

  void _clearUserForm() {
    _userNameController.clear();
    _userEmailController.clear();
    _userPhoneController.clear();
    _userOpenDaysController.clear();
    _userOpenHoursController.clear();
    _userCancelDeadlineController.clear();
    _userBookingMode = 'PRIVATE';
    _userReservationPolicy = 'AUTO_CONFIRM';
  }

  void _clearMemberAccountForm() {
    _accountNameController.clear();
    _accountEmailController.clear();
  }

  Future<void> _saveOrganization() async {
    final selected = _selectedOrganization;
    if (selected == null) return;

    setState(() => _savingOrganization = true);
    try {
      await _dio.put(
        '/admin/organizations/${selected.id}',
        data: {
          'name': _orgNameController.text.trim(),
          'description': _orgDescriptionController.text.trim().isEmpty
              ? null
              : _orgDescriptionController.text.trim(),
          'planType': _orgPlanType,
          'maxAdminCount':
              int.tryParse(_orgMaxAdminController.text.trim()) ?? 1,
          'maxMemberCount':
              int.tryParse(_orgMaxMemberController.text.trim()) ?? 30,
          'bookingMode': _orgBookingMode,
          'reservationPolicy': _orgReservationPolicy,
          'reservationOpenDaysBefore':
              int.tryParse(_orgOpenDaysController.text.trim()) ?? 30,
          'reservationOpenHoursBefore':
              int.tryParse(_orgOpenHoursController.text.trim()) ?? 0,
          'reservationCancelDeadlineMinutes':
              int.tryParse(_orgCancelDeadlineController.text.trim()) ?? 120,
        },
      );
      await _loadOrganizations(selectedId: selected.id);
      await _loadDashboard();
      _showSuccess('센터 정보를 수정했습니다');
    } on DioException catch (e) {
      _showError(e.response?.data?['error'] as String? ?? '센터 수정에 실패했습니다');
    } finally {
      if (mounted) {
        setState(() => _savingOrganization = false);
      }
    }
  }

  Future<void> _saveUser() async {
    final selected = _selectedUser;
    if (selected == null) return;

    setState(() => _savingUser = true);
    try {
      await _dio.put(
        '/admin/users/${selected.id}',
        data: {
          'name': _userNameController.text.trim(),
          'email': _userEmailController.text.trim(),
          'phone': _userPhoneController.text.trim().isEmpty
              ? null
              : _userPhoneController.text.trim(),
          'bookingMode': _userBookingMode,
          'reservationPolicy': _userReservationPolicy,
          'reservationOpenDaysBefore':
              int.tryParse(_userOpenDaysController.text.trim()) ?? 30,
          'reservationOpenHoursBefore':
              int.tryParse(_userOpenHoursController.text.trim()) ?? 0,
          'reservationCancelDeadlineMinutes':
              int.tryParse(_userCancelDeadlineController.text.trim()) ?? 120,
        },
      );
      await _loadUsers(selectedId: selected.id);
      _showSuccess('유저 정보를 수정했습니다');
    } on DioException catch (e) {
      _showError(e.response?.data?['error'] as String? ?? '유저 수정에 실패했습니다');
    } finally {
      if (mounted) {
        setState(() => _savingUser = false);
      }
    }
  }

  Future<void> _saveMemberAccount() async {
    final selected = _selectedMemberAccount;
    if (selected == null) return;

    setState(() => _savingMemberAccount = true);
    try {
      await _dio.put(
        '/admin/member-accounts/${selected.id}',
        data: {
          'name': _accountNameController.text.trim(),
          'email': _accountEmailController.text.trim(),
        },
      );
      await _loadMemberAccounts(selectedId: selected.id);
      _showSuccess('회원 계정 정보를 수정했습니다');
    } on DioException catch (e) {
      _showError(e.response?.data?['error'] as String? ?? '회원 계정 수정에 실패했습니다');
    } finally {
      if (mounted) {
        setState(() => _savingMemberAccount = false);
      }
    }
  }

  Future<void> _deleteOrganization(
    _AdminOrganizationRecord organization,
  ) async {
    final confirmed = await _confirm(
      title: '센터 삭제',
      message:
          '${organization.name} 센터를 삭제하면 회원, 예약, 패키지, 세션까지 함께 제거됩니다. 계속할까요?',
      confirmLabel: '센터 삭제',
    );
    if (!confirmed) return;

    try {
      await _dio.delete('/admin/organizations/${organization.id}');
      await _loadOrganizations();
      await _loadDashboard();
      await _loadReports();
      _showSuccess('센터를 삭제했습니다');
    } on DioException catch (e) {
      _showError(e.response?.data?['error'] as String? ?? '센터 삭제에 실패했습니다');
    }
  }

  Future<void> _deleteUser(_AdminUserRecord user) async {
    final confirmed = await _confirm(
      title: '유저 삭제',
      message: '${user.name} 계정을 삭제하면 소속 센터 연결과 관련 설정이 함께 정리됩니다. 계속할까요?',
      confirmLabel: '유저 삭제',
    );
    if (!confirmed) return;

    try {
      await _dio.delete('/admin/users/${user.id}');
      await _loadUsers();
      await _loadOrganizations();
      await _loadDashboard();
      await _loadReports();
      _showSuccess('유저를 삭제했습니다');
    } on DioException catch (e) {
      _showError(e.response?.data?['error'] as String? ?? '유저 삭제에 실패했습니다');
    }
  }

  Future<void> _deleteMemberAccount(_AdminMemberAccountRecord account) async {
    final confirmed = await _confirm(
      title: '회원 계정 삭제',
      message: '${account.name} 회원 계정을 삭제하면 연결된 회원 링크가 해제됩니다. 계속할까요?',
      confirmLabel: '회원 계정 삭제',
    );
    if (!confirmed) return;

    try {
      await _dio.delete('/admin/member-accounts/${account.id}');
      await _loadMemberAccounts();
      await _loadDashboard();
      await _loadReports();
      _showSuccess('회원 계정을 삭제했습니다');
    } on DioException catch (e) {
      _showError(e.response?.data?['error'] as String? ?? '회원 계정 삭제에 실패했습니다');
    }
  }

  Future<void> _showCreateUserDialog() async {
    final emailController = TextEditingController();
    final passwordController = TextEditingController();
    final nameController = TextEditingController();
    final phoneController = TextEditingController();
    bool isSaving = false;

    await showDialog<void>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return AlertDialog(
              title: const Text('관리자 유저 생성'),
              content: SizedBox(
                width: 420,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextField(
                        controller: nameController,
                        decoration: const InputDecoration(labelText: '이름'),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: emailController,
                        decoration: const InputDecoration(labelText: '이메일'),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: passwordController,
                        obscureText: true,
                        decoration: const InputDecoration(labelText: '초기 비밀번호'),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: phoneController,
                        decoration: const InputDecoration(labelText: '전화번호'),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isSaving ? null : () => Navigator.pop(context),
                  child: const Text('취소'),
                ),
                FilledButton(
                  onPressed: isSaving
                      ? null
                      : () async {
                          setStateDialog(() => isSaving = true);
                          try {
                            final response = await _dio.post(
                              '/admin/users',
                              data: {
                                'name': nameController.text.trim(),
                                'email': emailController.text.trim(),
                                'password': passwordController.text.trim(),
                                'phone': phoneController.text.trim().isEmpty
                                    ? null
                                    : phoneController.text.trim(),
                              },
                            );
                            if (!mounted || !context.mounted) return;
                            Navigator.pop(context);
                            final created = _AdminUserRecord.fromJson(
                              response.data as Map<String, dynamic>,
                            );
                            await _loadUsers(selectedId: created.id);
                            await _loadDashboard();
                            _showSuccess('관리자 유저를 생성했습니다');
                          } on DioException catch (e) {
                            if (!mounted) return;
                            setStateDialog(() => isSaving = false);
                            _showError(
                              e.response?.data?['error'] as String? ??
                                  '유저 생성에 실패했습니다',
                            );
                          }
                        },
                  child: const Text('생성'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _showCreateOrganizationDialog() async {
    if (_users.isEmpty) {
      _showError('센터를 만들기 전에 먼저 관리자 유저를 생성해 주세요');
      return;
    }

    final nameController = TextEditingController();
    final descriptionController = TextEditingController();
    String? ownerUserId = _users.first.id;
    String planType = 'FREE';
    bool isSaving = false;

    await showDialog<void>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return AlertDialog(
              title: const Text('센터 생성'),
              content: SizedBox(
                width: 460,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextField(
                        controller: nameController,
                        decoration: const InputDecoration(labelText: '센터명'),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: descriptionController,
                        maxLines: 3,
                        minLines: 2,
                        decoration: const InputDecoration(labelText: '설명'),
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        key: ValueKey('create-org-owner-$ownerUserId'),
                        initialValue: ownerUserId,
                        decoration: const InputDecoration(
                          labelText: 'OWNER 유저',
                        ),
                        items: _users
                            .map(
                              (user) => DropdownMenuItem(
                                value: user.id,
                                child: Text('${user.name} · ${user.email}'),
                              ),
                            )
                            .toList(),
                        onChanged: (value) =>
                            setStateDialog(() => ownerUserId = value),
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        key: ValueKey('create-org-plan-$planType'),
                        initialValue: planType,
                        decoration: const InputDecoration(labelText: '플랜'),
                        items: const [
                          DropdownMenuItem(value: 'FREE', child: Text('FREE')),
                          DropdownMenuItem(
                            value: 'BASIC',
                            child: Text('BASIC'),
                          ),
                          DropdownMenuItem(value: 'PRO', child: Text('PRO')),
                          DropdownMenuItem(
                            value: 'ENTERPRISE',
                            child: Text('ENTERPRISE'),
                          ),
                        ],
                        onChanged: (value) {
                          if (value == null) return;
                          setStateDialog(() => planType = value);
                        },
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isSaving ? null : () => Navigator.pop(context),
                  child: const Text('취소'),
                ),
                FilledButton(
                  onPressed: isSaving || ownerUserId == null
                      ? null
                      : () async {
                          setStateDialog(() => isSaving = true);
                          try {
                            final response = await _dio.post(
                              '/admin/organizations',
                              data: {
                                'name': nameController.text.trim(),
                                'description':
                                    descriptionController.text.trim().isEmpty
                                    ? null
                                    : descriptionController.text.trim(),
                                'ownerUserId': ownerUserId,
                                'planType': planType,
                              },
                            );
                            if (!mounted || !context.mounted) return;
                            Navigator.pop(context);
                            final created = _AdminOrganizationRecord.fromJson(
                              response.data as Map<String, dynamic>,
                            );
                            await _loadOrganizations(selectedId: created.id);
                            await _loadUsers(selectedId: ownerUserId);
                            await _loadDashboard();
                            _showSuccess('센터를 생성했습니다');
                          } on DioException catch (e) {
                            if (!mounted) return;
                            setStateDialog(() => isSaving = false);
                            _showError(
                              e.response?.data?['error'] as String? ??
                                  '센터 생성에 실패했습니다',
                            );
                          }
                        },
                  child: const Text('생성'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _showCreateMemberAccountDialog() async {
    final nameController = TextEditingController();
    final emailController = TextEditingController();
    final passwordController = TextEditingController();
    bool isSaving = false;

    await showDialog<void>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return AlertDialog(
              title: const Text('회원 계정 생성'),
              content: SizedBox(
                width: 420,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextField(
                        controller: nameController,
                        decoration: const InputDecoration(labelText: '이름'),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: emailController,
                        decoration: const InputDecoration(labelText: '이메일'),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: passwordController,
                        obscureText: true,
                        decoration: const InputDecoration(labelText: '초기 비밀번호'),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isSaving ? null : () => Navigator.pop(context),
                  child: const Text('취소'),
                ),
                FilledButton(
                  onPressed: isSaving
                      ? null
                      : () async {
                          setStateDialog(() => isSaving = true);
                          try {
                            final response = await _dio.post(
                              '/admin/member-accounts',
                              data: {
                                'name': nameController.text.trim(),
                                'email': emailController.text.trim(),
                                'password': passwordController.text.trim(),
                              },
                            );
                            if (!mounted || !context.mounted) return;
                            Navigator.pop(context);
                            final created = _AdminMemberAccountRecord.fromJson(
                              response.data as Map<String, dynamic>,
                            );
                            await _loadMemberAccounts(selectedId: created.id);
                            await _loadDashboard();
                            _showSuccess('회원 계정을 생성했습니다');
                          } on DioException catch (e) {
                            if (!mounted) return;
                            setStateDialog(() => isSaving = false);
                            _showError(
                              e.response?.data?['error'] as String? ??
                                  '회원 계정 생성에 실패했습니다',
                            );
                          }
                        },
                  child: const Text('생성'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _showAddCenterMemberDialog(_AdminOrganizationRecord org) async {
    final existingUserIds = org.memberships.map((item) => item.user.id).toSet();
    final candidates = _users
        .where((user) => !existingUserIds.contains(user.id))
        .toList();
    if (candidates.isEmpty) {
      _showError('추가할 수 있는 유저가 없습니다');
      return;
    }

    String? userId = candidates.first.id;
    String role = 'STAFF';
    bool isSaving = false;

    await showDialog<void>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return AlertDialog(
              title: Text('${org.name}에 관리자 추가'),
              content: SizedBox(
                width: 440,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DropdownButtonFormField<String>(
                      key: ValueKey('add-member-user-$userId'),
                      initialValue: userId,
                      decoration: const InputDecoration(labelText: '유저'),
                      items: candidates
                          .map(
                            (user) => DropdownMenuItem(
                              value: user.id,
                              child: Text('${user.name} · ${user.email}'),
                            ),
                          )
                          .toList(),
                      onChanged: (value) =>
                          setStateDialog(() => userId = value),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      key: ValueKey('add-member-role-$role'),
                      initialValue: role,
                      decoration: const InputDecoration(labelText: '역할'),
                      items: const [
                        DropdownMenuItem(value: 'OWNER', child: Text('OWNER')),
                        DropdownMenuItem(
                          value: 'MANAGER',
                          child: Text('MANAGER'),
                        ),
                        DropdownMenuItem(value: 'STAFF', child: Text('STAFF')),
                        DropdownMenuItem(
                          value: 'VIEWER',
                          child: Text('VIEWER'),
                        ),
                      ],
                      onChanged: (value) {
                        if (value == null) return;
                        setStateDialog(() => role = value);
                      },
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isSaving ? null : () => Navigator.pop(context),
                  child: const Text('취소'),
                ),
                FilledButton(
                  onPressed: isSaving || userId == null
                      ? null
                      : () async {
                          setStateDialog(() => isSaving = true);
                          try {
                            await _dio.post(
                              '/admin/organizations/${org.id}/members',
                              data: {'userId': userId, 'role': role},
                            );
                            if (!mounted || !context.mounted) return;
                            Navigator.pop(context);
                            await _loadOrganizations(selectedId: org.id);
                            await _loadUsers(selectedId: userId);
                            await _loadDashboard();
                            _showSuccess('센터 소속을 추가했습니다');
                          } on DioException catch (e) {
                            if (!mounted) return;
                            setStateDialog(() => isSaving = false);
                            _showError(
                              e.response?.data?['error'] as String? ??
                                  '센터 소속 추가에 실패했습니다',
                            );
                          }
                        },
                  child: const Text('추가'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _showAddUserMembershipDialog(_AdminUserRecord user) async {
    final existingOrgIds = user.memberships
        .map((membership) => membership.organization.id)
        .toSet();
    final candidates = _organizations
        .where((organization) => !existingOrgIds.contains(organization.id))
        .toList();
    if (candidates.isEmpty) {
      _showError('추가할 수 있는 센터가 없습니다');
      return;
    }

    String? organizationId = candidates.first.id;
    String role = 'STAFF';
    bool isSaving = false;

    await showDialog<void>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return AlertDialog(
              title: Text('${user.name} 소속 센터 추가'),
              content: SizedBox(
                width: 440,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DropdownButtonFormField<String>(
                      key: ValueKey('add-user-org-$organizationId'),
                      initialValue: organizationId,
                      decoration: const InputDecoration(labelText: '센터'),
                      items: candidates
                          .map(
                            (organization) => DropdownMenuItem(
                              value: organization.id,
                              child: Text(organization.name),
                            ),
                          )
                          .toList(),
                      onChanged: (value) =>
                          setStateDialog(() => organizationId = value),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      key: ValueKey('add-user-role-$role'),
                      initialValue: role,
                      decoration: const InputDecoration(labelText: '역할'),
                      items: const [
                        DropdownMenuItem(value: 'OWNER', child: Text('OWNER')),
                        DropdownMenuItem(
                          value: 'MANAGER',
                          child: Text('MANAGER'),
                        ),
                        DropdownMenuItem(value: 'STAFF', child: Text('STAFF')),
                        DropdownMenuItem(
                          value: 'VIEWER',
                          child: Text('VIEWER'),
                        ),
                      ],
                      onChanged: (value) {
                        if (value == null) return;
                        setStateDialog(() => role = value);
                      },
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isSaving ? null : () => Navigator.pop(context),
                  child: const Text('취소'),
                ),
                FilledButton(
                  onPressed: isSaving || organizationId == null
                      ? null
                      : () async {
                          setStateDialog(() => isSaving = true);
                          try {
                            await _dio.post(
                              '/admin/organizations/$organizationId/members',
                              data: {'userId': user.id, 'role': role},
                            );
                            if (!mounted || !context.mounted) return;
                            Navigator.pop(context);
                            await _loadUsers(selectedId: user.id);
                            await _loadOrganizations(
                              selectedId: organizationId,
                            );
                            await _loadDashboard();
                            _showSuccess('유저 소속 센터를 추가했습니다');
                          } on DioException catch (e) {
                            if (!mounted) return;
                            setStateDialog(() => isSaving = false);
                            _showError(
                              e.response?.data?['error'] as String? ??
                                  '유저 소속 추가에 실패했습니다',
                            );
                          }
                        },
                  child: const Text('추가'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _updateOrganizationMembershipRole({
    required String organizationId,
    required String userId,
    required String role,
  }) async {
    try {
      await _dio.put(
        '/admin/organizations/$organizationId/members/$userId',
        data: {'role': role},
      );
      await _loadOrganizations(selectedId: organizationId);
      await _loadUsers(selectedId: userId);
      _showSuccess('역할을 변경했습니다');
    } on DioException catch (e) {
      _showError(e.response?.data?['error'] as String? ?? '역할 변경에 실패했습니다');
    }
  }

  Future<void> _removeOrganizationMembership({
    required String organizationId,
    required String userId,
    required String label,
  }) async {
    final confirmed = await _confirm(
      title: '센터 소속 제거',
      message: '$label님의 센터 소속을 제거할까요?',
      confirmLabel: '제거',
    );
    if (!confirmed) return;

    try {
      await _dio.delete('/admin/organizations/$organizationId/members/$userId');
      await _loadOrganizations(selectedId: organizationId);
      await _loadUsers(selectedId: userId);
      await _loadDashboard();
      _showSuccess('센터 소속을 제거했습니다');
    } on DioException catch (e) {
      _showError(e.response?.data?['error'] as String? ?? '센터 소속 제거에 실패했습니다');
    }
  }

  Future<void> _reviewJoinRequest({
    required _AdminOrganizationRecord organization,
    required _AdminJoinRequest request,
    required String action,
  }) async {
    String role = 'STAFF';
    if (action == 'APPROVE') {
      final approved = await showDialog<bool>(
        context: context,
        builder: (context) {
          return StatefulBuilder(
            builder: (context, setStateDialog) {
              return AlertDialog(
                title: const Text('합류 신청 승인'),
                content: DropdownButtonFormField<String>(
                  key: ValueKey('join-request-role-$role'),
                  initialValue: role,
                  decoration: const InputDecoration(labelText: '부여 역할'),
                  items: const [
                    DropdownMenuItem(value: 'MANAGER', child: Text('MANAGER')),
                    DropdownMenuItem(value: 'STAFF', child: Text('STAFF')),
                    DropdownMenuItem(value: 'VIEWER', child: Text('VIEWER')),
                  ],
                  onChanged: (value) {
                    if (value == null) return;
                    setStateDialog(() => role = value);
                  },
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('취소'),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('승인'),
                  ),
                ],
              );
            },
          );
        },
      );
      if (approved != true) return;
    } else {
      final confirmed = await _confirm(
        title: '합류 신청 거절',
        message: '${request.user.name}님의 합류 신청을 거절할까요?',
        confirmLabel: '거절',
      );
      if (!confirmed) return;
    }

    try {
      await _dio.put(
        '/admin/organizations/${organization.id}/join-requests/${request.id}',
        data: {'action': action, if (action == 'APPROVE') 'role': role},
      );
      await _loadOrganizations(selectedId: organization.id);
      await _loadUsers(selectedId: request.user.id);
      await _loadDashboard();
      _showSuccess(action == 'APPROVE' ? '합류 신청을 승인했습니다' : '합류 신청을 거절했습니다');
    } on DioException catch (e) {
      _showError(e.response?.data?['error'] as String? ?? '합류 신청 처리에 실패했습니다');
    }
  }

  Future<bool> _confirm({
    required String title,
    required String message,
    required String confirmLabel,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
    return result == true;
  }

  void _showSuccess(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  String _formatCurrency(int amount) {
    return '${NumberFormat('#,###').format(amount)}원';
  }

  T? _resolveSelectedRecord<T>({
    required List<T> items,
    required String? selectedId,
    required String Function(T item) getId,
  }) {
    if (items.isEmpty) return null;
    if (selectedId == null) return items.first;
    return items.where((item) => getId(item) == selectedId).firstOrNull ??
        items.first;
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = ref.watch(authProvider).user;

    if (currentUser?.isSuperAdmin != true) {
      return Scaffold(
        appBar: AppBar(title: const Text('관리자 콘솔')),
        body: const EmptyState(
          icon: Icons.lock_outline_rounded,
          message: '이 페이지는 허용된 서비스 관리자만 접근할 수 있습니다',
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('서비스 관리자 콘솔'),
        actions: [
          IconButton(
            tooltip: '새로고침',
            onPressed: _loadAll,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: _buildSummaryHeader(currentUser?.email),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Align(
              alignment: Alignment.centerLeft,
              child: TabBar(
                controller: _tabController,
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                tabs: const [
                  Tab(text: '센터'),
                  Tab(text: '유저'),
                  Tab(text: '회원 계정'),
                  Tab(text: '리포트'),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildOrganizationTab(),
                _buildUserTab(),
                _buildMemberAccountTab(),
                _buildReportTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryHeader(String? email) {
    if (_loadingDashboard) {
      return const ShimmerLoading(style: ShimmerStyle.stats, itemCount: 1);
    }
    if (_dashboardError != null) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          boxShadow: AppTheme.softShadow,
        ),
        child: Text(_dashboardError!),
      );
    }

    final dashboard = _dashboard;
    if (dashboard == null) return const SizedBox.shrink();

    return GradientCard(
      borderRadius: BorderRadius.circular(22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '전역 서비스 관리자',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.84),
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            email ?? '-',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 18),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _SummaryPill(
                label: '센터',
                value: '${dashboard.organizationCount}',
              ),
              _SummaryPill(label: '관리자 유저', value: '${dashboard.userCount}'),
              _SummaryPill(label: '회원', value: '${dashboard.memberCount}'),
              _SummaryPill(
                label: '회원 계정',
                value: '${dashboard.memberAccountCount}',
              ),
              _SummaryPill(
                label: '합류 대기',
                value: '${dashboard.pendingJoinRequestCount}',
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildOrganizationTab() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 1100;
        final listPane = _buildOrganizationListPane();
        final detailPane = _buildOrganizationDetailPane();

        if (isWide) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(width: 370, child: listPane),
                const SizedBox(width: 16),
                Expanded(child: detailPane),
              ],
            ),
          );
        }

        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          children: [
            SizedBox(height: 440, child: listPane),
            const SizedBox(height: 16),
            detailPane,
          ],
        );
      },
    );
  }

  Widget _buildUserTab() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 1100;
        final listPane = _buildUserListPane();
        final detailPane = _buildUserDetailPane();

        if (isWide) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(width: 370, child: listPane),
                const SizedBox(width: 16),
                Expanded(child: detailPane),
              ],
            ),
          );
        }

        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          children: [
            SizedBox(height: 440, child: listPane),
            const SizedBox(height: 16),
            detailPane,
          ],
        );
      },
    );
  }

  Widget _buildMemberAccountTab() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 1100;
        final listPane = _buildMemberAccountListPane();
        final detailPane = _buildMemberAccountDetailPane();

        if (isWide) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(width: 370, child: listPane),
                const SizedBox(width: 16),
                Expanded(child: detailPane),
              ],
            ),
          );
        }

        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          children: [
            SizedBox(height: 440, child: listPane),
            const SizedBox(height: 16),
            detailPane,
          ],
        );
      },
    );
  }

  Widget _buildReportTab() {
    if (_loadingReports) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: ShimmerLoading(style: ShimmerStyle.card, itemCount: 6),
      );
    }

    if (_reportError != null) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: _PanelCard(
          child: _InlineError(message: _reportError!, onRetry: _loadReports),
        ),
      );
    }

    final report = _reportOverview;
    if (report == null) return const SizedBox.shrink();

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      children: [
        _PanelCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '센터별 운영 요약',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 12),
              ...report.centers.map(
                (center) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _ReportRow(
                    title: center.name,
                    subtitle:
                        '회원 ${center.memberCount}명 · 관리자 ${center.adminCount}명 · 예약 ${center.totalReservations}건 · 완료 수업 ${center.completedSessions}건',
                    metrics: [
                      '총매출 ${_formatCurrency(center.totalRevenue)}',
                      '이번달 ${_formatCurrency(center.monthRevenue)}',
                      '합류대기 ${center.pendingJoinRequestCount}건',
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _PanelCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '유저별 운영 요약',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 12),
              ...report.users.map(
                (user) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _ReportRow(
                    title: user.name,
                    subtitle:
                        '${user.email} · 센터 ${user.centerCount}개 · 예약 ${user.totalReservations}건 · 수업 ${user.totalSessions}건',
                    metrics: [
                      '전용패키지 매출 ${_formatCurrency(user.adminPackageRevenue)}',
                      '이번달 ${_formatCurrency(user.monthAdminPackageRevenue)}',
                      '노쇼 ${user.noShowSessions}건 / 지각 ${user.lateSessions}건',
                    ],
                    badge: user.isSuperAdmin ? 'SUPER ADMIN' : null,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildOrganizationListPane() {
    return _PanelCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  '센터 목록',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                ),
              ),
              FilledButton.icon(
                onPressed: _showCreateOrganizationDialog,
                icon: const Icon(Icons.add_business_rounded, size: 18),
                label: const Text('센터 생성'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _SearchBar(
            controller: _orgSearchController,
            hintText: '센터명, 설명, 초대코드 검색',
            onSearch: _loadOrganizations,
          ),
          const SizedBox(height: 12),
          Expanded(
            child: _loadingOrganizations
                ? const ShimmerLoading(style: ShimmerStyle.card, itemCount: 5)
                : _orgError != null
                ? _InlineError(message: _orgError!, onRetry: _loadOrganizations)
                : _organizations.isEmpty
                ? const EmptyState(
                    icon: Icons.business_outlined,
                    message: '표시할 센터가 없습니다',
                  )
                : ListView.separated(
                    itemCount: _organizations.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final item = _organizations[index];
                      final selected = item.id == _selectedOrganization?.id;
                      return _SelectableItemCard(
                        selected: selected,
                        title: item.name,
                        subtitle:
                            '관리자 ${item.counts.admins}명 · 회원 ${item.counts.members}명 · 합류대기 ${item.joinRequests.length}건',
                        trailing: Text(
                          item.planType,
                          style: TextStyle(
                            color: selected
                                ? AppTheme.primaryColor
                                : Colors.grey.shade600,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        onTap: () => _loadOrganizationDetail(item.id),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildUserListPane() {
    return _PanelCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  '유저 목록',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                ),
              ),
              FilledButton.icon(
                onPressed: _showCreateUserDialog,
                icon: const Icon(Icons.person_add_alt_1_rounded, size: 18),
                label: const Text('유저 생성'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _SearchBar(
            controller: _userSearchController,
            hintText: '이름, 이메일, 전화번호 검색',
            onSearch: _loadUsers,
          ),
          const SizedBox(height: 12),
          Expanded(
            child: _loadingUsers
                ? const ShimmerLoading(style: ShimmerStyle.card, itemCount: 5)
                : _userError != null
                ? _InlineError(message: _userError!, onRetry: _loadUsers)
                : _users.isEmpty
                ? const EmptyState(
                    icon: Icons.person_outline_rounded,
                    message: '표시할 유저가 없습니다',
                  )
                : ListView.separated(
                    itemCount: _users.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final item = _users[index];
                      final selected = item.id == _selectedUser?.id;
                      return _SelectableItemCard(
                        selected: selected,
                        title: item.name,
                        subtitle:
                            '${item.email}\n소속 ${item.memberships.length}개 센터',
                        trailing: item.isSuperAdmin
                            ? _TagPill(label: 'SUPER', color: Colors.amber)
                            : null,
                        onTap: () => _loadUserDetail(item.id),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildMemberAccountListPane() {
    return _PanelCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  '회원 계정 목록',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                ),
              ),
              FilledButton.icon(
                onPressed: _showCreateMemberAccountDialog,
                icon: const Icon(Icons.person_add_rounded, size: 18),
                label: const Text('회원 생성'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _SearchBar(
            controller: _accountSearchController,
            hintText: '이름, 이메일 검색',
            onSearch: _loadMemberAccounts,
          ),
          const SizedBox(height: 12),
          Expanded(
            child: _loadingMemberAccounts
                ? const ShimmerLoading(style: ShimmerStyle.card, itemCount: 5)
                : _memberAccountError != null
                ? _InlineError(
                    message: _memberAccountError!,
                    onRetry: _loadMemberAccounts,
                  )
                : _memberAccounts.isEmpty
                ? const EmptyState(
                    icon: Icons.badge_outlined,
                    message: '표시할 회원 계정이 없습니다',
                  )
                : ListView.separated(
                    itemCount: _memberAccounts.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final item = _memberAccounts[index];
                      final selected = item.id == _selectedMemberAccount?.id;
                      return _SelectableItemCard(
                        selected: selected,
                        title: item.name,
                        subtitle:
                            '${item.email}\n연결 회원 ${item.linkedMembers.length}명',
                        onTap: () => _loadMemberAccountDetail(item.id),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildOrganizationDetailPane() {
    final org = _selectedOrganization;
    if (org == null) {
      return const _PanelCard(
        child: EmptyState(
          icon: Icons.business_center_outlined,
          message: '센터를 선택하면 상세 정보가 표시됩니다',
        ),
      );
    }

    return _PanelCard(
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        org.name,
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '초대코드 ${org.inviteCode} · 생성 ${org.createdAtLabel}',
                        style: TextStyle(color: Colors.grey.shade600),
                      ),
                    ],
                  ),
                ),
                FilledButton.icon(
                  onPressed: _savingOrganization ? null : _saveOrganization,
                  icon: _savingOrganization
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.save_outlined),
                  label: const Text('센터 저장'),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: () => _deleteOrganization(org),
                  icon: const Icon(Icons.delete_outline_rounded),
                  label: const Text('센터 삭제'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.redAccent,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _MiniStatCard(label: '관리자', value: '${org.counts.admins}명'),
                _MiniStatCard(label: '회원', value: '${org.counts.members}명'),
                _MiniStatCard(label: '패키지', value: '${org.counts.packages}개'),
                _MiniStatCard(
                  label: '예약',
                  value: '${org.counts.reservations}건',
                ),
              ],
            ),
            const SizedBox(height: 20),
            const Text(
              '센터 정보 수정',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 12),
            _FormSection(
              children: [
                _LabeledField(
                  label: '센터명',
                  child: TextField(controller: _orgNameController),
                ),
                _LabeledField(
                  label: '설명',
                  child: TextField(
                    controller: _orgDescriptionController,
                    maxLines: 3,
                    minLines: 2,
                  ),
                ),
                Row(
                  children: [
                    Expanded(
                      child: _LabeledField(
                        label: '플랜',
                        child: DropdownButtonFormField<String>(
                          key: ValueKey('org-plan-$_orgPlanType'),
                          initialValue: _orgPlanType,
                          items: const [
                            DropdownMenuItem(
                              value: 'FREE',
                              child: Text('FREE'),
                            ),
                            DropdownMenuItem(
                              value: 'BASIC',
                              child: Text('BASIC'),
                            ),
                            DropdownMenuItem(value: 'PRO', child: Text('PRO')),
                            DropdownMenuItem(
                              value: 'ENTERPRISE',
                              child: Text('ENTERPRISE'),
                            ),
                          ],
                          onChanged: (value) {
                            if (value == null) return;
                            setState(() => _orgPlanType = value);
                          },
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _LabeledField(
                        label: '예약 공개 방식',
                        child: DropdownButtonFormField<String>(
                          key: ValueKey('org-booking-$_orgBookingMode'),
                          initialValue: _orgBookingMode,
                          items: const [
                            DropdownMenuItem(
                              value: 'PRIVATE',
                              child: Text('비공개'),
                            ),
                            DropdownMenuItem(
                              value: 'PUBLIC',
                              child: Text('공개'),
                            ),
                          ],
                          onChanged: (value) {
                            if (value == null) return;
                            setState(() => _orgBookingMode = value);
                          },
                        ),
                      ),
                    ),
                  ],
                ),
                Row(
                  children: [
                    Expanded(
                      child: _LabeledField(
                        label: '확정 정책',
                        child: DropdownButtonFormField<String>(
                          key: ValueKey('org-policy-$_orgReservationPolicy'),
                          initialValue: _orgReservationPolicy,
                          items: const [
                            DropdownMenuItem(
                              value: 'AUTO_CONFIRM',
                              child: Text('자동 확정'),
                            ),
                            DropdownMenuItem(
                              value: 'REQUEST_APPROVAL',
                              child: Text('승인 필요'),
                            ),
                          ],
                          onChanged: (value) {
                            if (value == null) return;
                            setState(() => _orgReservationPolicy = value);
                          },
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _LabeledField(
                        label: '관리자 정원',
                        child: TextField(
                          controller: _orgMaxAdminController,
                          keyboardType: TextInputType.number,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _LabeledField(
                        label: '회원 정원',
                        child: TextField(
                          controller: _orgMaxMemberController,
                          keyboardType: TextInputType.number,
                        ),
                      ),
                    ),
                  ],
                ),
                Row(
                  children: [
                    Expanded(
                      child: _LabeledField(
                        label: '예약 오픈 일수',
                        child: TextField(
                          controller: _orgOpenDaysController,
                          keyboardType: TextInputType.number,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _LabeledField(
                        label: '예약 오픈 시간',
                        child: TextField(
                          controller: _orgOpenHoursController,
                          keyboardType: TextInputType.number,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _LabeledField(
                        label: '취소 마감(분)',
                        child: TextField(
                          controller: _orgCancelDeadlineController,
                          keyboardType: TextInputType.number,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                const Expanded(
                  child: Text(
                    '센터 관리자 구성',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: () => _showAddCenterMemberDialog(org),
                  icon: const Icon(Icons.person_add_alt_1_rounded, size: 18),
                  label: const Text('관리자 추가'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ...org.memberships.map(
              (membership) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _EditableMembershipTile(
                  title: membership.user.name,
                  subtitle: membership.user.email,
                  role: membership.role,
                  trailingLabel: membership.user.isSuperAdmin
                      ? 'SUPER ADMIN'
                      : null,
                  onRoleSelected: (role) => _updateOrganizationMembershipRole(
                    organizationId: org.id,
                    userId: membership.user.id,
                    role: role,
                  ),
                  onRemove: () => _removeOrganizationMembership(
                    organizationId: org.id,
                    userId: membership.user.id,
                    label: membership.user.name,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              '센터 합류 신청',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 12),
            if (org.joinRequests.isEmpty)
              const _EmptyBlock(message: '현재 대기 중인 합류 신청이 없습니다')
            else
              ...org.joinRequests.map(
                (request) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _JoinRequestTile(
                    request: request,
                    onApprove: () => _reviewJoinRequest(
                      organization: org,
                      request: request,
                      action: 'APPROVE',
                    ),
                    onReject: () => _reviewJoinRequest(
                      organization: org,
                      request: request,
                      action: 'REJECT',
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildUserDetailPane() {
    final user = _selectedUser;
    if (user == null) {
      return const _PanelCard(
        child: EmptyState(
          icon: Icons.person_outline_rounded,
          message: '유저를 선택하면 상세 정보가 표시됩니다',
        ),
      );
    }

    return _PanelCard(
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            user.name,
                            style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          if (user.isSuperAdmin) ...[
                            const SizedBox(width: 10),
                            const _TagPill(
                              label: 'SUPER ADMIN',
                              color: Colors.amber,
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '${user.email} · 가입 ${user.createdAtLabel}',
                        style: TextStyle(color: Colors.grey.shade600),
                      ),
                    ],
                  ),
                ),
                FilledButton.icon(
                  onPressed: _savingUser ? null : _saveUser,
                  icon: _savingUser
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.save_outlined),
                  label: const Text('유저 저장'),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: () => _deleteUser(user),
                  icon: const Icon(Icons.delete_outline_rounded),
                  label: const Text('유저 삭제'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.redAccent,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            const Text(
              '유저 정보 수정',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 12),
            _FormSection(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: _LabeledField(
                        label: '이름',
                        child: TextField(controller: _userNameController),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _LabeledField(
                        label: '전화번호',
                        child: TextField(controller: _userPhoneController),
                      ),
                    ),
                  ],
                ),
                _LabeledField(
                  label: '이메일',
                  child: TextField(controller: _userEmailController),
                ),
                Row(
                  children: [
                    Expanded(
                      child: _LabeledField(
                        label: '예약 공개 방식',
                        child: DropdownButtonFormField<String>(
                          key: ValueKey('user-booking-$_userBookingMode'),
                          initialValue: _userBookingMode,
                          items: const [
                            DropdownMenuItem(
                              value: 'PRIVATE',
                              child: Text('비공개'),
                            ),
                            DropdownMenuItem(
                              value: 'PUBLIC',
                              child: Text('공개'),
                            ),
                          ],
                          onChanged: (value) {
                            if (value == null) return;
                            setState(() => _userBookingMode = value);
                          },
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _LabeledField(
                        label: '확정 정책',
                        child: DropdownButtonFormField<String>(
                          key: ValueKey('user-policy-$_userReservationPolicy'),
                          initialValue: _userReservationPolicy,
                          items: const [
                            DropdownMenuItem(
                              value: 'AUTO_CONFIRM',
                              child: Text('자동 확정'),
                            ),
                            DropdownMenuItem(
                              value: 'REQUEST_APPROVAL',
                              child: Text('승인 필요'),
                            ),
                          ],
                          onChanged: (value) {
                            if (value == null) return;
                            setState(() => _userReservationPolicy = value);
                          },
                        ),
                      ),
                    ),
                  ],
                ),
                Row(
                  children: [
                    Expanded(
                      child: _LabeledField(
                        label: '예약 오픈 일수',
                        child: TextField(
                          controller: _userOpenDaysController,
                          keyboardType: TextInputType.number,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _LabeledField(
                        label: '예약 오픈 시간',
                        child: TextField(
                          controller: _userOpenHoursController,
                          keyboardType: TextInputType.number,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _LabeledField(
                        label: '취소 마감(분)',
                        child: TextField(
                          controller: _userCancelDeadlineController,
                          keyboardType: TextInputType.number,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                const Expanded(
                  child: Text(
                    '소속 센터',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: () => _showAddUserMembershipDialog(user),
                  icon: const Icon(Icons.add_link_rounded, size: 18),
                  label: const Text('센터 소속 추가'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (user.memberships.isEmpty)
              const _EmptyBlock(message: '현재 소속된 센터가 없습니다')
            else
              ...user.memberships.map(
                (membership) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _EditableMembershipTile(
                    title: membership.organization.name,
                    subtitle: '등록 ${membership.createdAtLabel}',
                    role: membership.role,
                    onRoleSelected: (role) => _updateOrganizationMembershipRole(
                      organizationId: membership.organization.id,
                      userId: user.id,
                      role: role,
                    ),
                    onRemove: () => _removeOrganizationMembership(
                      organizationId: membership.organization.id,
                      userId: user.id,
                      label: user.name,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildMemberAccountDetailPane() {
    final account = _selectedMemberAccount;
    if (account == null) {
      return const _PanelCard(
        child: EmptyState(
          icon: Icons.badge_outlined,
          message: '회원 계정을 선택하면 상세 정보가 표시됩니다',
        ),
      );
    }

    return _PanelCard(
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        account.name,
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '${account.email} · 생성 ${account.createdAtLabel}',
                        style: TextStyle(color: Colors.grey.shade600),
                      ),
                    ],
                  ),
                ),
                FilledButton.icon(
                  onPressed: _savingMemberAccount ? null : _saveMemberAccount,
                  icon: _savingMemberAccount
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.save_outlined),
                  label: const Text('회원 저장'),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: () => _deleteMemberAccount(account),
                  icon: const Icon(Icons.delete_outline_rounded),
                  label: const Text('회원 계정 삭제'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.redAccent,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            const Text(
              '회원 계정 수정',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 12),
            _FormSection(
              children: [
                _LabeledField(
                  label: '이름',
                  child: TextField(controller: _accountNameController),
                ),
                _LabeledField(
                  label: '이메일',
                  child: TextField(controller: _accountEmailController),
                ),
              ],
            ),
            const SizedBox(height: 20),
            const Text(
              '연결된 회원',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 12),
            if (account.linkedMembers.isEmpty)
              const _EmptyBlock(message: '연결된 회원이 없습니다')
            else
              ...account.linkedMembers.map(
                (member) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _LinkedMemberTile(member: member),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _AdminDashboardStats {
  final int organizationCount;
  final int userCount;
  final int memberCount;
  final int memberAccountCount;
  final int pendingJoinRequestCount;

  const _AdminDashboardStats({
    required this.organizationCount,
    required this.userCount,
    required this.memberCount,
    required this.memberAccountCount,
    required this.pendingJoinRequestCount,
  });

  factory _AdminDashboardStats.fromJson(Map<String, dynamic> json) {
    return _AdminDashboardStats(
      organizationCount: json['organizationCount'] as int? ?? 0,
      userCount: json['userCount'] as int? ?? 0,
      memberCount: json['memberCount'] as int? ?? 0,
      memberAccountCount: json['memberAccountCount'] as int? ?? 0,
      pendingJoinRequestCount: json['pendingJoinRequestCount'] as int? ?? 0,
    );
  }
}

class _AdminOrganizationRecord {
  final String id;
  final String name;
  final String? description;
  final String inviteCode;
  final String planType;
  final int maxAdminCount;
  final int maxMemberCount;
  final String bookingMode;
  final String reservationPolicy;
  final int reservationOpenDaysBefore;
  final int reservationOpenHoursBefore;
  final int reservationCancelDeadlineMinutes;
  final DateTime createdAt;
  final _AdminCounts counts;
  final List<_AdminOrganizationMembership> memberships;
  final List<_AdminJoinRequest> joinRequests;

  const _AdminOrganizationRecord({
    required this.id,
    required this.name,
    required this.description,
    required this.inviteCode,
    required this.planType,
    required this.maxAdminCount,
    required this.maxMemberCount,
    required this.bookingMode,
    required this.reservationPolicy,
    required this.reservationOpenDaysBefore,
    required this.reservationOpenHoursBefore,
    required this.reservationCancelDeadlineMinutes,
    required this.createdAt,
    required this.counts,
    required this.memberships,
    this.joinRequests = const [],
  });

  factory _AdminOrganizationRecord.fromJson(Map<String, dynamic> json) {
    return _AdminOrganizationRecord(
      id: json['id'] as String,
      name: json['name'] as String? ?? '',
      description: json['description'] as String?,
      inviteCode: json['inviteCode'] as String? ?? '',
      planType: json['planType'] as String? ?? 'FREE',
      maxAdminCount: json['maxAdminCount'] as int? ?? 1,
      maxMemberCount: json['maxMemberCount'] as int? ?? 30,
      bookingMode: json['bookingMode'] as String? ?? 'PRIVATE',
      reservationPolicy: json['reservationPolicy'] as String? ?? 'AUTO_CONFIRM',
      reservationOpenDaysBefore:
          json['reservationOpenDaysBefore'] as int? ?? 30,
      reservationOpenHoursBefore:
          json['reservationOpenHoursBefore'] as int? ?? 0,
      reservationCancelDeadlineMinutes:
          json['reservationCancelDeadlineMinutes'] as int? ?? 120,
      createdAt: DateTime.parse(json['createdAt'] as String),
      counts: _AdminCounts.fromJson(
        json['counts'] as Map<String, dynamic>? ?? {},
      ),
      memberships: (json['memberships'] as List? ?? const [])
          .map(
            (item) => _AdminOrganizationMembership.fromJson(
              item as Map<String, dynamic>,
            ),
          )
          .toList(),
    );
  }

  _AdminOrganizationRecord copyWith({List<_AdminJoinRequest>? joinRequests}) {
    return _AdminOrganizationRecord(
      id: id,
      name: name,
      description: description,
      inviteCode: inviteCode,
      planType: planType,
      maxAdminCount: maxAdminCount,
      maxMemberCount: maxMemberCount,
      bookingMode: bookingMode,
      reservationPolicy: reservationPolicy,
      reservationOpenDaysBefore: reservationOpenDaysBefore,
      reservationOpenHoursBefore: reservationOpenHoursBefore,
      reservationCancelDeadlineMinutes: reservationCancelDeadlineMinutes,
      createdAt: createdAt,
      counts: counts,
      memberships: memberships,
      joinRequests: joinRequests ?? this.joinRequests,
    );
  }

  String get createdAtLabel => DateFormat('yyyy.MM.dd').format(createdAt);
}

class _AdminUserRecord {
  final String id;
  final String email;
  final String name;
  final String? phone;
  final String bookingMode;
  final String reservationPolicy;
  final int reservationOpenDaysBefore;
  final int reservationOpenHoursBefore;
  final int reservationCancelDeadlineMinutes;
  final bool isSuperAdmin;
  final DateTime createdAt;
  final List<_AdminUserMembership> memberships;

  const _AdminUserRecord({
    required this.id,
    required this.email,
    required this.name,
    required this.phone,
    required this.bookingMode,
    required this.reservationPolicy,
    required this.reservationOpenDaysBefore,
    required this.reservationOpenHoursBefore,
    required this.reservationCancelDeadlineMinutes,
    required this.isSuperAdmin,
    required this.createdAt,
    required this.memberships,
  });

  factory _AdminUserRecord.fromJson(Map<String, dynamic> json) {
    return _AdminUserRecord(
      id: json['id'] as String,
      email: json['email'] as String? ?? '',
      name: json['name'] as String? ?? '',
      phone: json['phone'] as String?,
      bookingMode: json['bookingMode'] as String? ?? 'PRIVATE',
      reservationPolicy: json['reservationPolicy'] as String? ?? 'AUTO_CONFIRM',
      reservationOpenDaysBefore:
          json['reservationOpenDaysBefore'] as int? ?? 30,
      reservationOpenHoursBefore:
          json['reservationOpenHoursBefore'] as int? ?? 0,
      reservationCancelDeadlineMinutes:
          json['reservationCancelDeadlineMinutes'] as int? ?? 120,
      isSuperAdmin: json['isSuperAdmin'] as bool? ?? false,
      createdAt: DateTime.parse(json['createdAt'] as String),
      memberships: (json['memberships'] as List? ?? const [])
          .map(
            (item) =>
                _AdminUserMembership.fromJson(item as Map<String, dynamic>),
          )
          .toList(),
    );
  }

  String get createdAtLabel => DateFormat('yyyy.MM.dd').format(createdAt);
}

class _AdminMemberAccountRecord {
  final String id;
  final String email;
  final String name;
  final DateTime createdAt;
  final List<_AdminLinkedMember> linkedMembers;

  const _AdminMemberAccountRecord({
    required this.id,
    required this.email,
    required this.name,
    required this.createdAt,
    required this.linkedMembers,
  });

  factory _AdminMemberAccountRecord.fromJson(Map<String, dynamic> json) {
    return _AdminMemberAccountRecord(
      id: json['id'] as String,
      email: json['email'] as String? ?? '',
      name: json['name'] as String? ?? '',
      createdAt: DateTime.parse(json['createdAt'] as String),
      linkedMembers: (json['linkedMembers'] as List? ?? const [])
          .map(
            (item) => _AdminLinkedMember.fromJson(item as Map<String, dynamic>),
          )
          .toList(),
    );
  }

  String get createdAtLabel => DateFormat('yyyy.MM.dd').format(createdAt);
}

class _AdminReportOverview {
  final List<_AdminCenterReportRecord> centers;
  final List<_AdminUserReportRecord> users;

  const _AdminReportOverview({required this.centers, required this.users});

  factory _AdminReportOverview.fromJson(Map<String, dynamic> json) {
    return _AdminReportOverview(
      centers: (json['centers'] as List? ?? const [])
          .map(
            (item) =>
                _AdminCenterReportRecord.fromJson(item as Map<String, dynamic>),
          )
          .toList(),
      users: (json['users'] as List? ?? const [])
          .map(
            (item) =>
                _AdminUserReportRecord.fromJson(item as Map<String, dynamic>),
          )
          .toList(),
    );
  }
}

class _AdminCenterReportRecord {
  final String id;
  final String name;
  final int memberCount;
  final int adminCount;
  final int totalReservations;
  final int completedSessions;
  final int totalRevenue;
  final int monthRevenue;
  final int pendingJoinRequestCount;

  const _AdminCenterReportRecord({
    required this.id,
    required this.name,
    required this.memberCount,
    required this.adminCount,
    required this.totalReservations,
    required this.completedSessions,
    required this.totalRevenue,
    required this.monthRevenue,
    required this.pendingJoinRequestCount,
  });

  factory _AdminCenterReportRecord.fromJson(Map<String, dynamic> json) {
    return _AdminCenterReportRecord(
      id: json['id'] as String,
      name: json['name'] as String? ?? '',
      memberCount: json['memberCount'] as int? ?? 0,
      adminCount: json['adminCount'] as int? ?? 0,
      totalReservations: json['totalReservations'] as int? ?? 0,
      completedSessions: json['completedSessions'] as int? ?? 0,
      totalRevenue: json['totalRevenue'] as int? ?? 0,
      monthRevenue: json['monthRevenue'] as int? ?? 0,
      pendingJoinRequestCount: json['pendingJoinRequestCount'] as int? ?? 0,
    );
  }
}

class _AdminUserReportRecord {
  final String id;
  final String name;
  final String email;
  final bool isSuperAdmin;
  final int centerCount;
  final int totalReservations;
  final int totalSessions;
  final int adminPackageRevenue;
  final int monthAdminPackageRevenue;
  final int noShowSessions;
  final int lateSessions;

  const _AdminUserReportRecord({
    required this.id,
    required this.name,
    required this.email,
    required this.isSuperAdmin,
    required this.centerCount,
    required this.totalReservations,
    required this.totalSessions,
    required this.adminPackageRevenue,
    required this.monthAdminPackageRevenue,
    required this.noShowSessions,
    required this.lateSessions,
  });

  factory _AdminUserReportRecord.fromJson(Map<String, dynamic> json) {
    return _AdminUserReportRecord(
      id: json['id'] as String,
      name: json['name'] as String? ?? '',
      email: json['email'] as String? ?? '',
      isSuperAdmin: json['isSuperAdmin'] as bool? ?? false,
      centerCount: json['centerCount'] as int? ?? 0,
      totalReservations: json['totalReservations'] as int? ?? 0,
      totalSessions: json['totalSessions'] as int? ?? 0,
      adminPackageRevenue: json['adminPackageRevenue'] as int? ?? 0,
      monthAdminPackageRevenue: json['monthAdminPackageRevenue'] as int? ?? 0,
      noShowSessions: json['noShowSessions'] as int? ?? 0,
      lateSessions: json['lateSessions'] as int? ?? 0,
    );
  }
}

class _AdminCounts {
  final int admins;
  final int members;
  final int packages;
  final int reservations;

  const _AdminCounts({
    required this.admins,
    required this.members,
    required this.packages,
    required this.reservations,
  });

  factory _AdminCounts.fromJson(Map<String, dynamic> json) {
    return _AdminCounts(
      admins: json['admins'] as int? ?? 0,
      members: json['members'] as int? ?? 0,
      packages: json['packages'] as int? ?? 0,
      reservations: json['reservations'] as int? ?? 0,
    );
  }
}

class _AdminOrganizationMembership {
  final String id;
  final String role;
  final _AdminUserReference user;

  const _AdminOrganizationMembership({
    required this.id,
    required this.role,
    required this.user,
  });

  factory _AdminOrganizationMembership.fromJson(Map<String, dynamic> json) {
    return _AdminOrganizationMembership(
      id: json['id'] as String,
      role: json['role'] as String? ?? '',
      user: _AdminUserReference.fromJson(json['user'] as Map<String, dynamic>),
    );
  }
}

class _AdminJoinRequest {
  final String id;
  final String? message;
  final DateTime createdAt;
  final _AdminUserReference user;

  const _AdminJoinRequest({
    required this.id,
    required this.message,
    required this.createdAt,
    required this.user,
  });

  factory _AdminJoinRequest.fromJson(Map<String, dynamic> json) {
    return _AdminJoinRequest(
      id: json['id'] as String,
      message: json['message'] as String?,
      createdAt: DateTime.parse(json['createdAt'] as String),
      user: _AdminUserReference.fromJson(json['user'] as Map<String, dynamic>),
    );
  }

  String get createdAtLabel => DateFormat('yyyy.MM.dd HH:mm').format(createdAt);
}

class _AdminUserReference {
  final String id;
  final String name;
  final String email;
  final bool isSuperAdmin;

  const _AdminUserReference({
    required this.id,
    required this.name,
    required this.email,
    required this.isSuperAdmin,
  });

  factory _AdminUserReference.fromJson(Map<String, dynamic> json) {
    return _AdminUserReference(
      id: json['id'] as String,
      name: json['name'] as String? ?? '',
      email: json['email'] as String? ?? '',
      isSuperAdmin: json['isSuperAdmin'] as bool? ?? false,
    );
  }
}

class _AdminUserMembership {
  final String id;
  final String role;
  final DateTime createdAt;
  final _AdminOrganizationReference organization;

  const _AdminUserMembership({
    required this.id,
    required this.role,
    required this.createdAt,
    required this.organization,
  });

  factory _AdminUserMembership.fromJson(Map<String, dynamic> json) {
    return _AdminUserMembership(
      id: json['id'] as String,
      role: json['role'] as String? ?? '',
      createdAt: DateTime.parse(json['createdAt'] as String),
      organization: _AdminOrganizationReference.fromJson(
        json['organization'] as Map<String, dynamic>,
      ),
    );
  }

  String get createdAtLabel => DateFormat('yyyy.MM.dd').format(createdAt);
}

class _AdminLinkedMember {
  final String id;
  final String name;
  final String status;
  final _AdminOrganizationReference organization;

  const _AdminLinkedMember({
    required this.id,
    required this.name,
    required this.status,
    required this.organization,
  });

  factory _AdminLinkedMember.fromJson(Map<String, dynamic> json) {
    return _AdminLinkedMember(
      id: json['id'] as String,
      name: json['name'] as String? ?? '',
      status: json['status'] as String? ?? 'ACTIVE',
      organization: _AdminOrganizationReference.fromJson(
        json['organization'] as Map<String, dynamic>,
      ),
    );
  }
}

class _AdminOrganizationReference {
  final String id;
  final String name;

  const _AdminOrganizationReference({required this.id, required this.name});

  factory _AdminOrganizationReference.fromJson(Map<String, dynamic> json) {
    return _AdminOrganizationReference(
      id: json['id'] as String,
      name: json['name'] as String? ?? '',
    );
  }
}

class _SummaryPill extends StatelessWidget {
  final String label;
  final String value;

  const _SummaryPill({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(16),
      ),
      child: RichText(
        text: TextSpan(
          children: [
            TextSpan(
              text: '$label ',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.82),
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            TextSpan(
              text: value,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PanelCard extends StatelessWidget {
  final Widget child;

  const _PanelCard({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        boxShadow: AppTheme.softShadow,
      ),
      padding: const EdgeInsets.all(18),
      child: child,
    );
  }
}

class _MiniStatCard extends StatelessWidget {
  final String label;
  final String value;

  const _MiniStatCard({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 132,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF6F8FC),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}

class _SelectableItemCard extends StatelessWidget {
  final bool selected;
  final String title;
  final String subtitle;
  final Widget? trailing;
  final VoidCallback onTap;

  const _SelectableItemCard({
    required this.selected,
    required this.title,
    required this.subtitle,
    this.trailing,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFFF1F7FF) : const Color(0xFFF8FAFD),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: selected ? AppTheme.primaryColor : const Color(0xFFE4EAF2),
            width: selected ? 1.4 : 1,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade600,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
            if (trailing != null) ...[const SizedBox(width: 12), trailing!],
          ],
        ),
      ),
    );
  }
}

class _SearchBar extends StatelessWidget {
  final TextEditingController controller;
  final String hintText;
  final Future<void> Function() onSearch;

  const _SearchBar({
    required this.controller,
    required this.hintText,
    required this.onSearch,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: controller,
            decoration: InputDecoration(
              hintText: hintText,
              prefixIcon: const Icon(Icons.search_rounded),
            ),
            onSubmitted: (_) => onSearch(),
          ),
        ),
        const SizedBox(width: 10),
        FilledButton(onPressed: onSearch, child: const Text('검색')),
      ],
    );
  }
}

class _InlineError extends StatelessWidget {
  final String message;
  final Future<void> Function() onRetry;

  const _InlineError({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.error_outline, color: Colors.red.shade300, size: 34),
          const SizedBox(height: 10),
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 12),
          OutlinedButton(onPressed: onRetry, child: const Text('다시 시도')),
        ],
      ),
    );
  }
}

class _FormSection extends StatelessWidget {
  final List<Widget> children;

  const _FormSection({required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFD),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        children:
            children
                .expand((child) => [child, const SizedBox(height: 14)])
                .toList()
              ..removeLast(),
      ),
    );
  }
}

class _LabeledField extends StatelessWidget {
  final String label;
  final Widget child;

  const _LabeledField({required this.label, required this.child});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: Colors.grey.shade700,
          ),
        ),
        const SizedBox(height: 8),
        child,
      ],
    );
  }
}

class _TagPill extends StatelessWidget {
  final String label;
  final Color color;

  const _TagPill({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          color: color,
        ),
      ),
    );
  }
}

class _EditableMembershipTile extends StatelessWidget {
  final String title;
  final String subtitle;
  final String role;
  final String? trailingLabel;
  final ValueChanged<String> onRoleSelected;
  final VoidCallback onRemove;

  const _EditableMembershipTile({
    required this.title,
    required this.subtitle,
    required this.role,
    this.trailingLabel,
    required this.onRoleSelected,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFD),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE4EAF2)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
              ],
            ),
          ),
          if (trailingLabel != null) ...[
            _TagPill(label: trailingLabel!, color: Colors.amber),
            const SizedBox(width: 8),
          ],
          PopupMenuButton<String>(
            onSelected: onRoleSelected,
            itemBuilder: (context) => const [
              PopupMenuItem(value: 'OWNER', child: Text('OWNER')),
              PopupMenuItem(value: 'MANAGER', child: Text('MANAGER')),
              PopupMenuItem(value: 'STAFF', child: Text('STAFF')),
              PopupMenuItem(value: 'VIEWER', child: Text('VIEWER')),
            ],
            child: _RoleChip(role: role),
          ),
          const SizedBox(width: 8),
          IconButton(
            onPressed: onRemove,
            icon: const Icon(Icons.remove_circle_outline_rounded),
            color: Colors.redAccent,
            tooltip: '소속 제거',
          ),
        ],
      ),
    );
  }
}

class _RoleChip extends StatelessWidget {
  final String role;

  const _RoleChip({required this.role});

  @override
  Widget build(BuildContext context) {
    final color = switch (role) {
      'OWNER' => Colors.deepPurple,
      'MANAGER' => Colors.blue,
      'STAFF' => Colors.teal,
      'VIEWER' => Colors.grey,
      _ => Colors.grey,
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            role,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
          const SizedBox(width: 6),
          Icon(Icons.expand_more_rounded, size: 16, color: color),
        ],
      ),
    );
  }
}

class _JoinRequestTile extends StatelessWidget {
  final _AdminJoinRequest request;
  final VoidCallback onApprove;
  final VoidCallback onReject;

  const _JoinRequestTile({
    required this.request,
    required this.onApprove,
    required this.onReject,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFD),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE4EAF2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          request.user.name,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        if (request.user.isSuperAdmin) ...[
                          const SizedBox(width: 8),
                          const _TagPill(label: 'SUPER', color: Colors.amber),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${request.user.email} · ${request.createdAtLabel}',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ),
              OutlinedButton(onPressed: onReject, child: const Text('거절')),
              const SizedBox(width: 8),
              FilledButton(onPressed: onApprove, child: const Text('승인')),
            ],
          ),
          if (request.message?.trim().isNotEmpty == true) ...[
            const SizedBox(height: 10),
            Text(
              request.message!.trim(),
              style: TextStyle(
                fontSize: 13,
                color: Colors.grey.shade700,
                height: 1.5,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _LinkedMemberTile extends StatelessWidget {
  final _AdminLinkedMember member;

  const _LinkedMemberTile({required this.member});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFD),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE4EAF2)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  member.name,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  member.organization.name,
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
              ],
            ),
          ),
          StatusBadge.fromStatus(switch (member.status) {
            'ACTIVE' => 'ACTIVE',
            'INACTIVE' => 'INACTIVE',
            _ => member.status,
          }),
        ],
      ),
    );
  }
}

class _EmptyBlock extends StatelessWidget {
  final String message;

  const _EmptyBlock({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFD),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE4EAF2)),
      ),
      child: Text(message, style: TextStyle(color: Colors.grey.shade600)),
    );
  }
}

class _ReportRow extends StatelessWidget {
  final String title;
  final String subtitle;
  final List<String> metrics;
  final String? badge;

  const _ReportRow({
    required this.title,
    required this.subtitle,
    required this.metrics,
    this.badge,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFD),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE4EAF2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (badge != null) _TagPill(label: badge!, color: Colors.amber),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: metrics
                .map(
                  (metric) => Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 7,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: const Color(0xFFE3E8EF)),
                    ),
                    child: Text(
                      metric,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade700,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                )
                .toList(),
          ),
        ],
      ),
    );
  }
}
