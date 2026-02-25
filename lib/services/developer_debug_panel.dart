// =============================================================================
// DEVELOPER DEBUG PANEL WITH ANIMATIONS
// =============================================================================
// Beautiful animated developer section for debugging and monitoring
// =============================================================================

import 'package:flutter/material.dart';
import 'dart:math' as math;
import 'app_logger.dart';
import 'device_state_manager.dart';
import 'precise_timing_service.dart';

class DeveloperDebugPanel extends StatefulWidget {
  const DeveloperDebugPanel({super.key});

  @override
  State<DeveloperDebugPanel> createState() => _DeveloperDebugPanelState();
}

class _DeveloperDebugPanelState extends State<DeveloperDebugPanel>
    with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  String _debugInfo = 'Loading...';
  bool _isExpanded = false;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat();
    _loadDebugInfo();
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  Future<void> _loadDebugInfo() async {
    final stateInfo = await DeviceStateManager().getDebugInfo();
    final timingInfo = await PreciseTimingService().getDebugInfo();
    final logs = AppLogger.logs.length;

    setState(() {
      _debugInfo =
          '''
$stateInfo

$timingInfo

Logs Recorded: $logs
Last Updated: ${DateTime.now().toIso8601String()}
''';
    });
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.all(12),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Colors.grey[900]!, Colors.grey[800]!],
          ),
          border: Border.all(color: Colors.cyan.withValues(alpha: 0.5)),
        ),
        child: Column(
          children: [
            // Header with animation
            GestureDetector(
              onTap: () => setState(() => _isExpanded = !_isExpanded),
              child: Container(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    // Animated indicator
                    AnimatedBuilder(
                      animation: _animController,
                      builder: (context, child) {
                        return Transform.rotate(
                          angle: _animController.value * 2 * math.pi,
                          child: Container(
                            width: 12,
                            height: 12,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.cyan,
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.cyan.withValues(alpha: 0.5),
                                  blurRadius: 8,
                                  spreadRadius: 2,
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text(
                        '🔧 DEVELOPER DEBUG PANEL',
                        style: TextStyle(
                          color: Colors.cyan,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                    ),
                    Icon(
                      _isExpanded ? Icons.expand_less : Icons.expand_more,
                      color: Colors.cyan,
                    ),
                  ],
                ),
              ),
            ),
            // Animated content
            if (_isExpanded) ...[
              const Divider(color: Colors.cyan, height: 1),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Live Debug Info with animation
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.black26,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: Colors.green.withValues(alpha: 0.3),
                          ),
                        ),
                        child: SelectableText(
                          _debugInfo,
                          style: const TextStyle(
                            color: Colors.green,
                            fontFamily: 'monospace',
                            fontSize: 11,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      // Action Buttons
                      Row(
                        children: [
                          Expanded(
                            child: _buildActionButton(
                              '🔄 REFRESH',
                              Colors.cyan,
                              _loadDebugInfo,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _buildActionButton(
                              '📋 LOGS',
                              Colors.amber,
                              () => _showLogs(context),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: _buildActionButton(
                              '🧹 CLEAR',
                              Colors.red,
                              () {
                                AppLogger.clear();
                                _loadDebugInfo();
                              },
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _buildActionButton(
                              '📊 SYNC',
                              Colors.purple,
                              () => _syncStates(context),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildActionButton(String label, Color color, VoidCallback onPressed) {
    return ElevatedButton(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: color.withValues(alpha: 0.8),
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(vertical: 10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      ),
      child: Text(
        label,
        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
      ),
    );
  }

  void _showLogs(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('📋 Recent Logs'),
        content: SizedBox(
          width: double.maxFinite,
          height: 400,
          child: ListView.builder(
            itemCount: AppLogger.logs.length,
            itemBuilder: (context, index) {
              final log = AppLogger.logs[AppLogger.logs.length - 1 - index];
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Text(
                  log,
                  style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
                ),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<void> _syncStates(BuildContext context) async {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Syncing states with native layer...')),
    );

    final stateManager = DeviceStateManager();
    final (locked, paid) = await stateManager.syncStateWithNative();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Sync complete: Locked=$locked, Paid=$paid'),
          backgroundColor: Colors.green,
        ),
      );
      await _loadDebugInfo();
    }
  }
}

/// Animated monitoring widget for real-time stats
class AnimatedStatsMonitor extends StatefulWidget {
  final int remainingDays;
  final bool isLocked;
  final bool isPaidInFull;

  const AnimatedStatsMonitor({
    super.key,
    required this.remainingDays,
    required this.isLocked,
    required this.isPaidInFull,
  });

  @override
  State<AnimatedStatsMonitor> createState() => _AnimatedStatsMonitorState();
}

class _AnimatedStatsMonitorState extends State<AnimatedStatsMonitor>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _buildStatCard(
          label: 'Days Left',
          value: '${widget.remainingDays}',
          icon: '⏱️',
          color: widget.remainingDays > 7 ? Colors.green : Colors.orange,
        ),
        _buildStatCard(
          label: 'Status',
          value: widget.isPaidInFull
              ? 'PAID'
              : widget.isLocked
              ? 'LOCKED'
              : 'ACTIVE',
          icon: widget.isPaidInFull
              ? '✅'
              : widget.isLocked
              ? '🔒'
              : '▶️',
          color: widget.isPaidInFull
              ? Colors.green
              : widget.isLocked
              ? Colors.red
              : Colors.blue,
        ),
      ],
    );
  }

  Widget _buildStatCard({
    required String label,
    required String value,
    required String icon,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        color: Colors.grey[900],
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Column(
        children: [
          Text(icon, style: const TextStyle(fontSize: 24)),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Text(label, style: TextStyle(color: Colors.grey[400], fontSize: 11)),
        ],
      ),
    );
  }
}
