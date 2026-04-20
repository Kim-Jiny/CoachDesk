import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/api_client.dart';
import '../../core/theme.dart';
import '../../providers/ui_settings_provider.dart';
import '../../widgets/common.dart';

class RevenueReportScreen extends ConsumerStatefulWidget {
  final DateTime? initialMonth;
  final String reportScope;

  const RevenueReportScreen({
    super.key,
    this.initialMonth,
    this.reportScope = 'center',
  });

  @override
  ConsumerState<RevenueReportScreen> createState() =>
      _RevenueReportScreenState();
}

class _RevenueReportScreenState extends ConsumerState<RevenueReportScreen> {
  late DateTime _selectedMonth;
  Map<String, dynamic>? _report;
  bool _isLoading = false;
  bool get _isAdminScope => widget.reportScope == 'admin';

  @override
  void initState() {
    super.initState();
    final initialMonth = widget.initialMonth ?? DateTime.now();
    _selectedMonth = DateTime(initialMonth.year, initialMonth.month, 1);
    _loadReport();
  }

  DateTime get _startDate =>
      DateTime(_selectedMonth.year, _selectedMonth.month, 1);

  DateTime get _endDate {
    final now = DateTime.now();
    if (_selectedMonth.year == now.year && _selectedMonth.month == now.month) {
      return now;
    }
    return DateTime(
      _selectedMonth.year,
      _selectedMonth.month + 1,
      0,
      23,
      59,
      59,
    );
  }

  bool get _isCurrentMonth {
    final now = DateTime.now();
    return _selectedMonth.year == now.year && _selectedMonth.month == now.month;
  }

  Future<void> _loadReport() async {
    setState(() => _isLoading = true);
    try {
      final dio = ref.read(dioProvider);
      final response = await dio.get(
        '/reports/revenue',
        queryParameters: {
          'startDate': DateFormat('yyyy-MM-dd').format(_startDate),
          'endDate': DateFormat('yyyy-MM-dd').format(_endDate),
          if (_isAdminScope) 'scope': 'admin',
        },
      );
      setState(() {
        _report = response.data as Map<String, dynamic>;
        _isLoading = false;
      });
    } catch (_) {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final formatter = NumberFormat('#,###');
    final hideRevenueAmount = ref.watch(hideRevenueAmountProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(_isAdminScope ? '관리자 매출 통계' : '센터 매출 통계'),
        actions: [
          IconButton(
            tooltip: hideRevenueAmount ? '금액 표시' : '금액 숨기기',
            onPressed: () {
              ref
                  .read(hideRevenueAmountProvider.notifier)
                  .toggleHideRevenueAmount();
            },
            icon: Icon(
              hideRevenueAmount
                  ? Icons.visibility_off_outlined
                  : Icons.visibility_outlined,
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          // Month selector
          Container(
            margin: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              boxShadow: AppTheme.softShadow,
            ),
            child: Row(
              children: [
                IconButton(
                  onPressed: () {
                    setState(() {
                      _selectedMonth = DateTime(
                        _selectedMonth.year,
                        _selectedMonth.month - 1,
                        1,
                      );
                    });
                    _loadReport();
                  },
                  icon: const Icon(Icons.chevron_left_rounded),
                ),
                Expanded(
                  child: Column(
                    children: [
                      Text(
                        DateFormat('yyyy년 M월', 'ko').format(_selectedMonth),
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${DateFormat('M/d', 'ko').format(_startDate)} - ${DateFormat('M/d', 'ko').format(_endDate)}',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade500,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: _isCurrentMonth
                      ? null
                      : () {
                          setState(() {
                            _selectedMonth = DateTime(
                              _selectedMonth.year,
                              _selectedMonth.month + 1,
                              1,
                            );
                          });
                          _loadReport();
                        },
                  icon: const Icon(Icons.chevron_right_rounded),
                ),
              ],
            ),
          ),
          Expanded(
            child: _isLoading
                ? const Center(
                    child: ShimmerLoading(
                      style: ShimmerStyle.card,
                      itemCount: 4,
                    ),
                  )
                : _report == null
                ? const EmptyState(
                    icon: Icons.bar_chart,
                    message: '데이터를 불러올 수 없습니다',
                  )
                : SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Total revenue gradient card
                        GradientCard(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '총 매출',
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.8),
                                  fontSize: 14,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                hideRevenueAmount
                                    ? '금액 숨김'
                                    : '${formatter.format(_report!['totalRevenue'] ?? 0)}원',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 30,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _isAdminScope
                                    ? '${_report!['count'] ?? 0}건 내 패키지 등록'
                                    : '${_report!['count'] ?? 0}건 등록',
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.7),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 20),

                        // Bar chart
                        _buildBarChart(formatter, hideRevenueAmount),
                        const SizedBox(height: 20),

                        // Details
                        Row(
                          children: [
                            const Expanded(
                              child: SectionHeader(title: '상세 내역'),
                            ),
                            Text(
                              DateFormat(
                                'yyyy년 M월',
                                'ko',
                              ).format(_selectedMonth),
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey.shade500,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        if ((_report!['details'] as List? ?? []).isEmpty)
                          EmptyState(
                            icon: Icons.receipt_long_outlined,
                            message: _isAdminScope
                                ? '해당 월에 내 관리자 패키지 매출이 없습니다'
                                : '해당 월에 등록된 패키지가 없습니다',
                          )
                        else
                          ...(_report!['details'] as List? ?? []).map((d) {
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 12,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(14),
                                  boxShadow: AppTheme.softShadow,
                                ),
                                child: Row(
                                  children: [
                                    CircleAvatar(
                                      radius: 18,
                                      backgroundColor: AppTheme.primaryColor
                                          .withValues(alpha: 0.1),
                                      child: Text(
                                        (d['member']?['name'] as String? ??
                                            '?')[0],
                                        style: const TextStyle(
                                          color: AppTheme.primaryColor,
                                          fontWeight: FontWeight.w600,
                                          fontSize: 13,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            d['member']?['name'] as String? ??
                                                '',
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w600,
                                              fontSize: 14,
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            d['package']?['name'] as String? ??
                                                '',
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: Colors.grey.shade500,
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            '${DateFormat('M월 d일', 'ko').format(DateTime.parse(d['purchaseDate'] as String))} 등록 · ${_paymentMethodLabel(d['paymentMethod'] as String?)}',
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: Colors.grey.shade500,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Text(
                                      hideRevenueAmount
                                          ? '숨김'
                                          : '${formatter.format(d['paidAmount'])}원',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                        fontSize: 14,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          }),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildBarChart(NumberFormat formatter, bool hideRevenueAmount) {
    final byMethod = _report!['byMethod'] as Map<String, dynamic>? ?? {};
    if (byMethod.isEmpty) return const SizedBox.shrink();
    if (hideRevenueAmount) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: AppTheme.softShadow,
        ),
        child: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '결제 수단별 매출',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
            SizedBox(height: 8),
            Text(
              '금액 숨기기가 활성화되어 있어 차트를 가렸습니다.',
              style: TextStyle(fontSize: 13, color: Colors.grey),
            ),
          ],
        ),
      );
    }

    final entries = byMethod.entries.toList();
    final maxValue = entries.fold<double>(0, (max, e) {
      final val = (e.value as num).toDouble();
      return val > max ? val : max;
    });

    final colors = {
      'CARD': Colors.blue,
      'CASH': AppTheme.successColor,
      'TRANSFER': Colors.orange,
    };

    final labels = {'CARD': '카드', 'CASH': '현금', 'TRANSFER': '이체'};

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: AppTheme.softShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '결제 수단별',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
          const SizedBox(height: 20),
          SizedBox(
            height: 180,
            child: BarChart(
              BarChartData(
                alignment: BarChartAlignment.spaceAround,
                maxY: maxValue * 1.2,
                barTouchData: BarTouchData(
                  touchTooltipData: BarTouchTooltipData(
                    getTooltipItem: (group, groupIndex, rod, rodIndex) {
                      return BarTooltipItem(
                        '${formatter.format(rod.toY.toInt())}원',
                        const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                          fontSize: 12,
                        ),
                      );
                    },
                  ),
                ),
                titlesData: FlTitlesData(
                  show: true,
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      getTitlesWidget: (value, meta) {
                        final idx = value.toInt();
                        if (idx < 0 || idx >= entries.length) {
                          return const SizedBox.shrink();
                        }
                        return Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            labels[entries[idx].key] ?? entries[idx].key,
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade600,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  leftTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  topTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  rightTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                ),
                borderData: FlBorderData(show: false),
                gridData: const FlGridData(show: false),
                barGroups: entries.asMap().entries.map((e) {
                  final color = colors[e.value.key] ?? Colors.grey;
                  return BarChartGroupData(
                    x: e.key,
                    barRods: [
                      BarChartRodData(
                        toY: (e.value.value as num).toDouble(),
                        color: color,
                        width: 28,
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(8),
                        ),
                      ),
                    ],
                  );
                }).toList(),
              ),
            ),
          ),
          const SizedBox(height: 16),
          // Legend
          Wrap(
            spacing: 16,
            children: entries.map((e) {
              final color = colors[e.key] ?? Colors.grey;
              return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '${labels[e.key] ?? e.key}: ${formatter.format(e.value)}원',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                  ),
                ],
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  String _paymentMethodLabel(String? method) {
    switch (method) {
      case 'CARD':
        return '카드';
      case 'CASH':
        return '현금';
      case 'TRANSFER':
        return '이체';
      default:
        return method ?? '-';
    }
  }
}
