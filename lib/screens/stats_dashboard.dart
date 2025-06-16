// File: lib/screens/stats_dashboard.dart

import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';

class StatsDashboardScreen extends StatefulWidget {
  final List<Map<String, dynamic>> readings;

  const StatsDashboardScreen({super.key, required this.readings});

  @override
  State<StatsDashboardScreen> createState() => _StatsDashboardScreenState();
}

class _StatsDashboardScreenState extends State<StatsDashboardScreen>
    with TickerProviderStateMixin {
  late AnimationController _fadeController;
  late AnimationController _slideController;
  late AnimationController _scaleController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;
  late Animation<double> _scaleAnimation;

  Map<String, int> networkTypeCount = {};
  Map<String, int> carrierCount = {};
  List<FlSpot> signalOverTime = [];
  String topCarrier = 'N/A';
  String strongestNetwork = 'N/A';
  double averageSignal = 0.0;
  int totalReadings = 0;

  Map<String, double> carrierAvgSignal = {};
  List<Map<String, dynamic>> hourlyStats = [];
  String weakestCarrier = 'N/A';
  String mostReliableCarrier = 'N/A';
  double maxSignal = 0.0;
  double minSignal = 100.0;
  double signalVariance = 0.0;
  int strongSignalCount = 0; // >80%
  int weakSignalCount = 0; // <30%
  int moderateSignalCount = 0; // 30-80%

  @override
  void initState() {
    super.initState();
    _setupAnimations();
    _processData();
    _startAnimations();
  }

  void _setupAnimations() {
    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 1200),
      vsync: this,
    );
    _slideController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    _scaleController = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _fadeController, curve: Curves.easeOutQuart),
    );
    _slideAnimation =
        Tween<Offset>(begin: const Offset(0, 0.3), end: Offset.zero).animate(
          CurvedAnimation(parent: _slideController, curve: Curves.easeOutCubic),
        );
    _scaleAnimation = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(parent: _scaleController, curve: Curves.elasticOut),
    );
  }

  void _startAnimations() {
    Future.delayed(const Duration(milliseconds: 100), () {
      _fadeController.forward();
    });
    Future.delayed(const Duration(milliseconds: 200), () {
      _slideController.forward();
    });
    Future.delayed(const Duration(milliseconds: 300), () {
      _scaleController.forward();
    });
  }

  void _processData() {
    networkTypeCount.clear();
    carrierCount.clear();
    signalOverTime.clear();

    if (widget.readings.isEmpty) return;

    double totalSignal = 0.0;
    for (int i = 0; i < widget.readings.length; i++) {
      final r = widget.readings[i];
      final carrier = r['carrier'] as String? ?? 'Unknown';
      final network = r['networkType'] as String? ?? 'Unknown';
      final intensity = (r['intensity'] as num?)?.toDouble() ?? 0.0;

      carrierCount[carrier] = (carrierCount[carrier] ?? 0) + 1;
      networkTypeCount[network] = (networkTypeCount[network] ?? 0) + 1;
      signalOverTime.add(FlSpot(i.toDouble(), intensity * 100));
      totalSignal += intensity;
    }

    totalReadings = widget.readings.length;
    averageSignal = totalReadings > 0
        ? (totalSignal / totalReadings) * 100
        : 0.0;

    topCarrier = carrierCount.entries.isEmpty
        ? 'N/A'
        : carrierCount.entries.reduce((a, b) => a.value > b.value ? a : b).key;

    strongestNetwork = networkTypeCount.entries.isEmpty
        ? 'N/A'
        : networkTypeCount.entries
              .reduce((a, b) => a.value > b.value ? a : b)
              .key;
    // Calculate additional statistics
    List<double> signalValues = [];
    Map<String, List<double>> carrierSignals = {};

    for (final r in widget.readings) {
      final carrier = r['carrier'] as String? ?? 'Unknown';
      final intensity = (r['intensity'] as num?)?.toDouble() ?? 0.0;
      final signalPercent = intensity * 100;

      signalValues.add(signalPercent);
      carrierSignals[carrier] = carrierSignals[carrier] ?? [];
      carrierSignals[carrier]!.add(signalPercent);

      // Count signal strength categories
      if (signalPercent > 80) {
        strongSignalCount++;
      } else if (signalPercent < 30) {
        weakSignalCount++;
      } else {
        moderateSignalCount++;
      }
    }

    // Calculate min/max
    if (signalValues.isNotEmpty) {
      maxSignal = signalValues.reduce((a, b) => a > b ? a : b);
      minSignal = signalValues.reduce((a, b) => a < b ? a : b);

      // Calculate variance
      final mean = signalValues.reduce((a, b) => a + b) / signalValues.length;
      signalVariance =
          signalValues
              .map((x) => (x - mean) * (x - mean))
              .reduce((a, b) => a + b) /
          signalValues.length;
    }

    // Calculate carrier averages
    carrierSignals.forEach((carrier, signals) {
      carrierAvgSignal[carrier] =
          signals.reduce((a, b) => a + b) / signals.length;
    });

    // Find weakest and most reliable carriers
    if (carrierAvgSignal.isNotEmpty) {
      weakestCarrier = carrierAvgSignal.entries
          .reduce((a, b) => a.value < b.value ? a : b)
          .key;
      mostReliableCarrier = carrierAvgSignal.entries
          .reduce((a, b) => a.value > b.value ? a : b)
          .key;
    }
  }

  @override
  void dispose() {
    _fadeController.dispose();
    _slideController.dispose();
    _scaleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: CustomScrollView(
        slivers: [
          _buildSliverAppBar(),
          SliverPadding(
            padding: const EdgeInsets.all(16),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                _buildOverviewCards(),
                const SizedBox(height: 24),
                _buildNetworkTypeChart(),
                const SizedBox(height: 24),
                _buildCarrierChart(),
                const SizedBox(height: 24),
                _buildSignalStrengthChart(),
                const SizedBox(height: 24),
                _buildSignalDistributionChart(),
                const SizedBox(height: 24),
                _buildCarrierComparisonChart(),
                const SizedBox(height: 24),
                _buildDetailedStats(),
                const SizedBox(height: 100), // Extra space at bottom
              ]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSliverAppBar() {
    return SliverAppBar(
      expandedHeight: 120,
      floating: false,
      pinned: true,
      elevation: 0,
      backgroundColor: Theme.of(context).primaryColor,
      flexibleSpace: FlexibleSpaceBar(
        title: FadeTransition(
          opacity: _fadeAnimation,
          child: const Text(
            'Network Analytics',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
          ),
        ),
        background: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                Theme.of(context).primaryColor,
                Theme.of(context).primaryColor.withOpacity(0.8),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: Center(
            child: ScaleTransition(
              scale: _scaleAnimation,
              child: Icon(
                Icons.analytics_rounded,
                size: 60,
                color: Colors.white.withOpacity(0.3),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildOverviewCards() {
    return SlideTransition(
      position: _slideAnimation,
      child: FadeTransition(
        opacity: _fadeAnimation,
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: _buildStatCard(
                    title: 'Total Readings',
                    value: totalReadings.toString(),
                    icon: Icons.radar_rounded,
                    color: Colors.blue,
                    delay: 0,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildStatCard(
                    title: 'Avg Signal',
                    value: '${averageSignal.toStringAsFixed(1)}%',
                    icon: Icons.signal_cellular_alt_rounded,
                    color: Colors.green,
                    delay: 100,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _buildStatCard(
                    title: 'Max Signal',
                    value: '${maxSignal.toStringAsFixed(1)}%',
                    icon: Icons.trending_up_rounded,
                    color: Colors.orange,
                    delay: 200,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildStatCard(
                    title: 'Min Signal',
                    value: '${minSignal.toStringAsFixed(1)}%',
                    icon: Icons.trending_down_rounded,
                    color: Colors.red,
                    delay: 300,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatCard({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
    required int delay,
  }) {
    return TweenAnimationBuilder<double>(
      duration: Duration(milliseconds: 800 + delay),
      tween: Tween(begin: 0.0, end: 1.0),
      curve: Curves.elasticOut,
      builder: (context, animation, child) {
        return Transform.scale(
          scale: animation,
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.08),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon, color: color, size: 24),
                ),
                const SizedBox(height: 12),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 14,
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurface.withOpacity(0.7),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildNetworkTypeChart() {
    return _buildAnimatedCard(
      title: 'Network Type Distribution',
      icon: Icons.network_cell_rounded,
      delay: 200,
      child: Container(
        height: 280,
        padding: const EdgeInsets.all(16),
        child: networkTypeCount.isEmpty
            ? _buildEmptyState('No network data available')
            : Row(
                children: [
                  Expanded(flex: 2, child: _buildPieChart(networkTypeCount)),
                  const SizedBox(width: 16),
                  Expanded(child: _buildLegend(networkTypeCount)),
                ],
              ),
      ),
    );
  }

  Widget _buildCarrierChart() {
    return _buildAnimatedCard(
      title: 'Carrier Distribution',
      icon: Icons.cell_tower_rounded,
      delay: 300,
      child: Container(
        height: 280,
        padding: const EdgeInsets.all(16),
        child: carrierCount.isEmpty
            ? _buildEmptyState('No carrier data available')
            : Column(
                children: [
                  Expanded(child: _buildBarChart(carrierCount)),
                  const SizedBox(height: 16),
                  Text(
                    'Most Active: $topCarrier',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Theme.of(context).primaryColor,
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildSignalStrengthChart() {
    return _buildAnimatedCard(
      title: 'Signal Strength Timeline',
      icon: Icons.timeline_rounded,
      delay: 400,
      child: Container(
        height: 350,
        padding: const EdgeInsets.all(16),
        child: signalOverTime.isEmpty
            ? _buildEmptyState('No signal data available')
            : _buildLineChart(signalOverTime),
      ),
    );
  }

  Widget _buildAnimatedCard({
    required String title,
    required IconData icon,
    required Widget child,
    required int delay,
  }) {
    return TweenAnimationBuilder<double>(
      duration: Duration(milliseconds: 600 + delay),
      tween: Tween(begin: 0.0, end: 1.0),
      curve: Curves.easeOutCubic,
      builder: (context, animation, _) {
        return Transform.translate(
          offset: Offset(0, 30 * (1 - animation)),
          child: Opacity(
            opacity: animation,
            child: Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: Theme.of(context).cardColor,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.08),
                    blurRadius: 15,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.all(20),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Theme.of(
                              context,
                            ).primaryColor.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(
                            icon,
                            color: Theme.of(context).primaryColor,
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          title,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                  child,
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildEmptyState(String message) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.analytics_outlined, size: 48, color: Colors.grey.shade400),
          const SizedBox(height: 16),
          Text(
            message,
            style: TextStyle(fontSize: 16, color: Colors.grey.shade600),
          ),
        ],
      ),
    );
  }

  Widget _buildPieChart(Map<String, int> data) {
    final total = data.values.fold(0, (a, b) => a + b);
    return TweenAnimationBuilder<double>(
      duration: const Duration(milliseconds: 1500),
      tween: Tween(begin: 0.0, end: 1.0),
      curve: Curves.easeOutCubic,
      builder: (context, animation, child) {
        return PieChart(
          PieChartData(
            sections: data.entries.map((entry) {
              final percentage = entry.value / total * 100;
              return PieChartSectionData(
                color: _getColorFor(entry.key),
                value: entry.value.toDouble() * animation,
                title: animation > 0.7 && percentage > 8
                    ? '${percentage.toStringAsFixed(1)}%'
                    : '',
                titleStyle: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
                radius: 80 * animation,
                titlePositionPercentageOffset: 0.6,
              );
            }).toList(),
            sectionsSpace: 2,
            centerSpaceRadius: 30,
          ),
        );
      },
    );
  }

  Widget _buildLegend(Map<String, int> data) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: data.entries.map((entry) {
        return TweenAnimationBuilder<double>(
          duration: const Duration(milliseconds: 800),
          tween: Tween(begin: 0.0, end: 1.0),
          curve: Curves.easeOutCubic,
          builder: (context, animation, child) {
            return Transform.translate(
              offset: Offset(20 * (1 - animation), 0),
              child: Opacity(
                opacity: animation,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      Container(
                        width: 16,
                        height: 16,
                        decoration: BoxDecoration(
                          color: _getColorFor(entry.key),
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '${entry.key} (${entry.value})',
                          style: const TextStyle(fontSize: 14),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      }).toList(),
    );
  }

  Widget _buildBarChart(Map<String, int> data) {
    final maxValue = data.values.isNotEmpty
        ? data.values.reduce((a, b) => a > b ? a : b)
        : 1;

    return TweenAnimationBuilder<double>(
      duration: const Duration(milliseconds: 1200),
      tween: Tween(begin: 0.0, end: 1.0),
      curve: Curves.easeOutCubic,
      builder: (context, animation, child) {
        return BarChart(
          BarChartData(
            maxY: maxValue.toDouble(),
            barGroups: data.entries.toList().asMap().entries.map((entry) {
              final index = entry.key;
              final data = entry.value;
              return BarChartGroupData(
                x: index,
                barRods: [
                  BarChartRodData(
                    toY: data.value.toDouble() * animation,
                    color: _getColorFor(data.key),
                    width: 30,
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(4),
                    ),
                  ),
                ],
              );
            }).toList(),
            titlesData: FlTitlesData(
              show: true,
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  getTitlesWidget: (value, meta) {
                    if (value.toInt() < data.length) {
                      final key = data.keys.toList()[value.toInt()];
                      return Container(
                        margin: const EdgeInsets.only(top: 8),
                        child: Text(
                          key.length > 6 ? '${key.substring(0, 6)}...' : key,
                          style: TextStyle(
                            fontSize: 11,
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurface.withOpacity(0.7),
                          ),
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      );
                    }
                    return const SizedBox();
                  },
                ),
              ),
              leftTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 40,
                  getTitlesWidget: (value, meta) {
                    return Text(
                      value.toInt().toString(),
                      style: const TextStyle(fontSize: 12),
                    );
                  },
                ),
              ),
              topTitles: const AxisTitles(
                sideTitles: SideTitles(showTitles: false),
              ),
              rightTitles: const AxisTitles(
                sideTitles: SideTitles(showTitles: false),
              ),
            ),
            gridData: FlGridData(show: false),
            borderData: FlBorderData(show: false),
          ),
        );
      },
    );
  }

  Widget _buildLineChart(List<FlSpot> data) {
    // Calculate better intervals and max values
    final maxY = data.isNotEmpty
        ? data.map((e) => e.y).reduce((a, b) => a > b ? a : b)
        : 100;
    final minY = data.isNotEmpty
        ? data.map((e) => e.y).reduce((a, b) => a < b ? a : b)
        : 0;
    final maxX = data.isNotEmpty
        ? data.map((e) => e.x).reduce((a, b) => a > b ? a : b)
        : 10;

    // Calculate smart intervals
    final yInterval = _calculateInterval((maxY - minY).toDouble());
    final xInterval = maxX > 20 ? (maxX / 8).ceil().toDouble() : 2.0;

    return TweenAnimationBuilder<double>(
      duration: const Duration(milliseconds: 1500),
      tween: Tween(begin: 0.0, end: 1.0),
      curve: Curves.easeOutCubic,
      builder: (context, animation, child) {
        final animatedData = data.map((spot) {
          return FlSpot(spot.x, spot.y * animation);
        }).toList();

        return Column(
          children: [
            // Chart Title and Legend
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Signal Strength Over Time',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Theme.of(context).primaryColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: Theme.of(context).primaryColor,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'Signal %',
                          style: TextStyle(
                            fontSize: 12,
                            color: Theme.of(context).primaryColor,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // The actual chart
            Expanded(
              child: LineChart(
                LineChartData(
                  minY: (minY - yInterval).clamp(0, double.infinity),
                  maxY: maxY + yInterval,
                  lineBarsData: [
                    LineChartBarData(
                      spots: animatedData,
                      isCurved: true,
                      curveSmoothness: 0.35,
                      color: Theme.of(context).primaryColor,
                      barWidth: 3,
                      belowBarData: BarAreaData(
                        show: true,
                        gradient: LinearGradient(
                          colors: [
                            Theme.of(context).primaryColor.withOpacity(0.3),
                            Theme.of(context).primaryColor.withOpacity(0.1),
                            Colors.transparent,
                          ],
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                        ),
                      ),
                      dotData: FlDotData(
                        show:
                            data.length <=
                            20, // Only show dots if not too many points
                        getDotPainter: (spot, percent, barData, index) {
                          return FlDotCirclePainter(
                            radius: 4,
                            color: Theme.of(context).primaryColor,
                            strokeWidth: 2,
                            strokeColor: Colors.white,
                          );
                        },
                      ),
                      // Add shadow effect
                      shadow: Shadow(
                        color: Theme.of(context).primaryColor.withOpacity(0.3),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ),
                  ],
                  gridData: FlGridData(
                    show: true,
                    drawVerticalLine: true,
                    horizontalInterval: yInterval,
                    verticalInterval: xInterval,
                    getDrawingHorizontalLine: (value) {
                      return FlLine(
                        color: Theme.of(context).dividerColor.withOpacity(0.3),
                        strokeWidth: 1,
                        dashArray: [5, 5], // Dashed lines
                      );
                    },
                    getDrawingVerticalLine: (value) {
                      return FlLine(
                        color: Theme.of(context).dividerColor.withOpacity(0.2),
                        strokeWidth: 1,
                        dashArray: [5, 5],
                      );
                    },
                  ),
                  borderData: FlBorderData(
                    show: true,
                    border: Border(
                      bottom: BorderSide(
                        color: Theme.of(context).dividerColor.withOpacity(0.5),
                        width: 1,
                      ),
                      left: BorderSide(
                        color: Theme.of(context).dividerColor.withOpacity(0.5),
                        width: 1,
                      ),
                    ),
                  ),
                  titlesData: FlTitlesData(
                    show: true,
                    // Bottom titles (X-axis) - Reading Number
                    bottomTitles: AxisTitles(
                      axisNameWidget: Container(
                        margin: const EdgeInsets.only(top: 12),
                        child: Text(
                          'Carriers',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurface.withOpacity(0.7),
                          ),
                        ),
                      ),
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 35,
                        interval: xInterval,
                        getTitlesWidget: (value, meta) {
                          if (value.toInt() >= 0 &&
                              value.toInt() < data.length) {
                            return Container(
                              margin: const EdgeInsets.only(top: 8),
                              child: Text(
                                '#${value.toInt() + 1}',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurface.withOpacity(0.6),
                                ),
                              ),
                            );
                          }
                          return const SizedBox();
                        },
                      ),
                    ),

                    // Left titles (Y-axis) - Signal Strength
                    leftTitles: AxisTitles(
                      axisNameWidget: null,
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 75,
                        interval: yInterval,
                        getTitlesWidget: (value, meta) {
                          if (value == meta.max)
                            return const SizedBox(); // Hide max value to avoid overlap
                          return Text(
                            '${value.toInt()}%',
                            style: TextStyle(
                              fontSize: 11,
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurface.withOpacity(0.6),
                            ),
                          );
                        },
                      ),
                    ),
                    topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                  ),
                  // Add touch interaction
                  lineTouchData: LineTouchData(
                    enabled: true,
                    touchTooltipData: LineTouchTooltipData(
                      getTooltipColor: (touchedSpot) =>
                          Theme.of(context).cardColor,
                      tooltipBorder: BorderSide(
                        color: Theme.of(context).dividerColor,
                        width: 1,
                      ),
                      tooltipMargin: 8,
                      getTooltipItems: (List<LineBarSpot> touchedBarSpots) {
                        return touchedBarSpots.map((barSpot) {
                          return LineTooltipItem(
                            'Reading #${barSpot.x.toInt()}\n${barSpot.y.toStringAsFixed(1)}% Signal',
                            TextStyle(
                              color: Theme.of(context).colorScheme.onSurface,
                              fontWeight: FontWeight.w500,
                              fontSize: 12,
                            ),
                          );
                        }).toList();
                      },
                    ),
                    touchCallback:
                        (FlTouchEvent event, LineTouchResponse? touchResponse) {
                          // Add haptic feedback when touching the chart
                          if (event is FlTapUpEvent &&
                              touchResponse?.lineBarSpots != null) {
                            // You can add HapticFeedback.lightImpact() here if you want
                          }
                        },
                  ),
                ),
              ),
            ),

            // Chart summary
            if (data.isNotEmpty)
              Container(
                margin: const EdgeInsets.only(top: 12),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: Theme.of(
                    context,
                  ).colorScheme.surfaceVariant.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _buildChartStat(
                      'Min',
                      '${minY.toStringAsFixed(1)}%',
                      Icons.trending_down,
                    ),
                    _buildChartStat(
                      'Max',
                      '${maxY.toStringAsFixed(1)}%',
                      Icons.trending_up,
                    ),
                    _buildChartStat(
                      'Avg',
                      '${(data.map((e) => e.y).reduce((a, b) => a + b) / data.length).toStringAsFixed(1)}%',
                      Icons.show_chart,
                    ),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }

  double _calculateInterval(double range) {
    if (range <= 0) return 20;
    if (range <= 50) return 10;
    if (range <= 100) return 20;
    if (range <= 200) return 25;
    return 50;
  }

  Widget _buildChartStat(String label, String value, IconData icon) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          icon,
          size: 16,
          color: Theme.of(context).primaryColor.withOpacity(0.7),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: Theme.of(context).colorScheme.onSurface,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            fontSize: 10,
            color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
          ),
        ),
      ],
    );
  }

  Widget _buildDetailedStats() {
    return _buildAnimatedCard(
      title: 'Detailed Statistics',
      icon: Icons.info_outline_rounded,
      delay: 500,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            _buildDetailRow(
              'Strongest Network',
              strongestNetwork,
              Icons.signal_cellular_alt,
            ),
            const Divider(height: 24),
            _buildDetailRow(
              'Most Active Carrier',
              topCarrier,
              Icons.cell_tower,
            ),
            const Divider(height: 24),
            _buildDetailRow(
              'Data Points Collected',
              totalReadings.toString(),
              Icons.dataset,
            ),
            const Divider(height: 24),
            _buildDetailRow(
              'Average Signal Strength',
              '${averageSignal.toStringAsFixed(1)}%',
              Icons.speed,
            ),
            const Divider(height: 24),
            _buildDetailRow(
              'Signal Variance',
              signalVariance.toStringAsFixed(2),
              Icons.scatter_plot,
            ),
            const Divider(height: 24),
            _buildDetailRow(
              'Weakest Carrier',
              weakestCarrier,
              Icons.signal_cellular_0_bar,
            ),
            const Divider(height: 24),
            _buildDetailRow(
              'Strong Signals (>80%)',
              '$strongSignalCount readings',
              Icons.signal_cellular_4_bar,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailRow(String label, String value, IconData icon) {
    return TweenAnimationBuilder<double>(
      duration: const Duration(milliseconds: 800),
      tween: Tween(begin: 0.0, end: 1.0),
      curve: Curves.easeOutCubic,
      builder: (context, animation, child) {
        return Transform.translate(
          offset: Offset(0, 10 * (1 - animation)),
          child: Opacity(
            opacity: animation,
            child: Row(
              children: [
                Icon(icon, size: 20, color: Theme.of(context).primaryColor),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    label,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).primaryColor,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildSignalDistributionChart() {
    return _buildAnimatedCard(
      title: 'Signal Strength Distribution',
      icon: Icons.pie_chart_rounded,
      delay: 450,
      child: Container(
        height: 280,
        padding: const EdgeInsets.all(16),
        child: totalReadings == 0
            ? _buildEmptyState('No signal data available')
            : Row(
                children: [
                  Expanded(flex: 2, child: _buildSignalDistributionPie()),
                  const SizedBox(width: 16),
                  Expanded(child: _buildSignalDistributionLegend()),
                ],
              ),
      ),
    );
  }

  Widget _buildSignalDistributionPie() {
    final data = {
      'Strong (>80%)': strongSignalCount,
      'Moderate (30-80%)': moderateSignalCount,
      'Weak (<30%)': weakSignalCount,
    };

    return TweenAnimationBuilder<double>(
      duration: const Duration(milliseconds: 1500),
      tween: Tween(begin: 0.0, end: 1.0),
      curve: Curves.easeOutCubic,
      builder: (context, animation, child) {
        return PieChart(
          PieChartData(
            sections: data.entries.map((entry) {
              final percentage = totalReadings > 0
                  ? entry.value / totalReadings * 100
                  : 0;
              Color color;
              switch (entry.key) {
                case 'Strong (>80%)':
                  color = Colors.green;
                  break;
                case 'Moderate (30-80%)':
                  color = Colors.orange;
                  break;
                default:
                  color = Colors.red;
              }

              return PieChartSectionData(
                color: color,
                value: entry.value.toDouble() * animation,
                title: animation > 0.7 && percentage > 5
                    ? '${percentage.toStringAsFixed(1)}%'
                    : '',
                titleStyle: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
                radius: 70 * animation,
                titlePositionPercentageOffset: 0.6,
              );
            }).toList(),
            sectionsSpace: 2,
            centerSpaceRadius: 25,
          ),
        );
      },
    );
  }

  Widget _buildSignalDistributionLegend() {
    final data = {
      'Strong (>80%)': strongSignalCount,
      'Moderate (30-80%)': moderateSignalCount,
      'Weak (<30%)': weakSignalCount,
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: data.entries.map((entry) {
        Color color;
        switch (entry.key) {
          case 'Strong (>80%)':
            color = Colors.green;
            break;
          case 'Moderate (30-80%)':
            color = Colors.orange;
            break;
          default:
            color = Colors.red;
        }

        return TweenAnimationBuilder<double>(
          duration: const Duration(milliseconds: 800),
          tween: Tween(begin: 0.0, end: 1.0),
          curve: Curves.easeOutCubic,
          builder: (context, animation, child) {
            return Transform.translate(
              offset: Offset(20 * (1 - animation), 0),
              child: Opacity(
                opacity: animation,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    children: [
                      Container(
                        width: 16,
                        height: 16,
                        decoration: BoxDecoration(
                          color: color,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              entry.key.split(' ')[0],
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            Text(
                              '${entry.value} readings',
                              style: TextStyle(
                                fontSize: 12,
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurface.withOpacity(0.7),
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
          },
        );
      }).toList(),
    );
  }

  Widget _buildCarrierComparisonChart() {
    return _buildAnimatedCard(
      title: 'Carrier Performance',
      icon: Icons.compare_arrows_rounded,
      delay: 500,
      child: Container(
        height: 300,
        padding: const EdgeInsets.all(16),
        child: carrierAvgSignal.isEmpty
            ? _buildEmptyState('No carrier performance data')
            : _buildCarrierPerformanceChart(),
      ),
    );
  }

  Widget _buildCarrierPerformanceChart() {
    final sortedCarriers = carrierAvgSignal.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return TweenAnimationBuilder<double>(
      duration: const Duration(milliseconds: 1200),
      tween: Tween(begin: 0.0, end: 1.0),
      curve: Curves.easeOutCubic,
      builder: (context, animation, child) {
        return Column(
          children: [
            Expanded(
              child: BarChart(
                BarChartData(
                  maxY: 100,
                  barGroups: sortedCarriers.asMap().entries.map((entry) {
                    final index = entry.key;
                    final carrier = entry.value;
                    return BarChartGroupData(
                      x: index,
                      barRods: [
                        BarChartRodData(
                          toY: carrier.value * animation,
                          color: _getColorFor(carrier.key),
                          width: 25,
                          borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(4),
                          ),
                          gradient: LinearGradient(
                            colors: [
                              _getColorFor(carrier.key),
                              _getColorFor(carrier.key).withOpacity(0.7),
                            ],
                            begin: Alignment.bottomCenter,
                            end: Alignment.topCenter,
                          ),
                        ),
                      ],
                    );
                  }).toList(),
                  titlesData: FlTitlesData(
                    show: true,
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        getTitlesWidget: (value, meta) {
                          if (value.toInt() < sortedCarriers.length) {
                            final carrier = sortedCarriers[value.toInt()].key;
                            return Container(
                              margin: const EdgeInsets.only(top: 8),
                              child: Text(
                                carrier.length > 8
                                    ? '${carrier.substring(0, 8)}...'
                                    : carrier,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurface.withOpacity(0.7),
                                ),
                                textAlign: TextAlign.center,
                              ),
                            );
                          }
                          return const SizedBox();
                        },
                      ),
                    ),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 45,
                        getTitlesWidget: (value, meta) {
                          return Text(
                            '${value.toInt()}%',
                            style: const TextStyle(fontSize: 11),
                          );
                        },
                      ),
                    ),
                    topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                  ),
                  gridData: FlGridData(show: true, horizontalInterval: 20),
                  borderData: FlBorderData(show: false),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Best Performer: ${mostReliableCarrier != 'N/A' ? mostReliableCarrier : 'No data'}',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Theme.of(context).primaryColor,
              ),
            ),
          ],
        );
      },
    );
  }

  Color _getColorFor(String key) {
    switch (key.toLowerCase()) {
      case '4g':
      case 'lte':
        return Colors.green;
      case '5g':
        return Colors.purple;
      case 'wi-fi':
      case 'wifi':
        return Colors.orange;
      case '3g':
        return Colors.blueGrey;
      case '2g':
        return Colors.grey;
      default:
        // Generate consistent colors for carriers
        final colors = [
          Colors.blue,
          Colors.red,
          Colors.teal,
          Colors.indigo,
          Colors.pink,
          Colors.amber,
          Colors.cyan,
          Colors.lime,
        ];
        return colors[key.hashCode % colors.length];
    }
  }
}
