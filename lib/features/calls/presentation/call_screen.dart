import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_theme.dart';
import '../../../services/auth_provider.dart';

enum CallState { ringing, connected, ended }

class CallData {
  final String userId;
  final String userName;
  final String? avatarUrl;
  final bool isVideoCall;
  final String? callId;

  CallData({
    required this.userId,
    required this.userName,
    this.avatarUrl,
    this.isVideoCall = false,
    this.callId,
  });
}

class CallScreen extends ConsumerStatefulWidget {
  final CallData callData;
  final bool isIncoming;

  const CallScreen({
    super.key,
    required this.callData,
    this.isIncoming = false,
  });

  @override
  ConsumerState<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends ConsumerState<CallScreen> {
  CallState _callState = CallState.ringing;
  bool _isMuted = false;
  bool _isSpeakerOff = false;
  bool _isVideoEnabled = true;
  Timer? _callTimer;
  int _secondsElapsed = 0;
  String? _callId;

  @override
  void initState() {
    super.initState();
    _callId = widget.callData.callId;
    if (!widget.isIncoming) {
      _startCall();
    }
  }

  @override
  void dispose() {
    _callTimer?.cancel();
    super.dispose();
  }

  Future<void> _startCall() async {
    final api = ref.read(apiServiceProvider);
    try {
      final call = await api.initiateCall(
        widget.callData.userId,
        widget.callData.isVideoCall ? 'Video' : 'Audio',
      );
      if (call.containsKey('id')) {
        _callId = call['id'].toString();
      }
    } catch (_) {}

    if (mounted) {
      setState(() {
        _callState = CallState.connected;
      });
      _startTimer();
    }
  }

  void _startTimer() {
    _callTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() {
          _secondsElapsed++;
        });
      }
    });
  }

  Future<void> _acceptCall() async {
    final api = ref.read(apiServiceProvider);
    if (_callId != null && _callId!.isNotEmpty) {
      try {
        await api.answerCall(_callId!);
      } catch (_) {}
    }
    if (mounted) {
      setState(() {
        _callState = CallState.connected;
      });
      _startTimer();
    }
  }

  Future<void> _rejectCall() async {
    final api = ref.read(apiServiceProvider);
    if (_callId != null && _callId!.isNotEmpty) {
      try {
        await api.rejectCall(_callId!);
      } catch (_) {}
    }
    if (mounted) {
      Navigator.pop(context);
    }
  }

  Future<void> _endCall() async {
    _callTimer?.cancel();
    final api = ref.read(apiServiceProvider);
    if (_callId != null && _callId!.isNotEmpty) {
      try {
        await api.endCall(_callId!);
      } catch (_) {}
    }
    if (mounted) {
      setState(() {
        _callState = CallState.ended;
      });
      Future.delayed(const Duration(milliseconds: 500), () {
        if (mounted) Navigator.pop(context);
      });
    }
  }

  String _formatTime(int totalSeconds) {
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              const Color(0xFF0c0e1a),
              AppTheme.surface.withValues(alpha: 0.9),
              const Color(0xFF0c0e1a),
            ],
          ),
        ),
        child: SafeArea(
          child: _callState == CallState.ended
              ? const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.call_end_rounded,
                          size: 64, color: AppTheme.error),
                      SizedBox(height: 16),
                      Text(
                        'Call Ended',
                        style: TextStyle(
                          fontSize: 22,
                          color: AppTheme.textPrimary,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      SizedBox(height: 8),
                      Text(
                        'The call has been disconnected',
                        style: TextStyle(
                          color: AppTheme.textMuted,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                )
              : Column(
                  children: [
                    const Spacer(flex: 2),
                    // Avatar with glow
                    Center(
                      child: Column(
                        children: [
                          Container(
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: AppTheme.primaryIndigo
                                      .withValues(alpha: 0.35),
                                  blurRadius: 50,
                                  spreadRadius: 10,
                                ),
                              ],
                            ),
                            child: CircleAvatar(
                              radius: 64,
                              backgroundColor: AppTheme.surfaceElevated,
                              child: Text(
                                widget.callData.userName[0]
                                    .toUpperCase(),
                                style: const TextStyle(
                                  fontSize: 52,
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 24),
                          Text(
                            widget.callData.userName,
                            style: const TextStyle(
                              fontSize: 28,
                              color: AppTheme.textPrimary,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            _callState == CallState.ringing
                                ? 'Incoming ${widget.callData.isVideoCall ? "Video" : "Voice"} Call...'
                                : _formatTime(_secondsElapsed),
                            style: const TextStyle(
                              fontSize: 16,
                              color: AppTheme.textMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Spacer(flex: 2),
                    // Incoming call buttons
                    if (_callState == CallState.ringing &&
                        widget.isIncoming)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 48),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            // Reject
                            Column(
                              children: [
                                Container(
                                  decoration: BoxDecoration(
                                    color: AppTheme.error
                                        .withValues(alpha: 0.9),
                                    shape: BoxShape.circle,
                                    boxShadow: [
                                      BoxShadow(
                                        color: AppTheme.error
                                            .withValues(alpha: 0.3),
                                        blurRadius: 16,
                                        spreadRadius: 2,
                                      ),
                                    ],
                                  ),
                                  child: IconButton(
                                    icon: const Icon(Icons.call_end_rounded,
                                        color: Colors.white, size: 28),
                                    onPressed: _rejectCall,
                                    iconSize: 28,
                                    padding: const EdgeInsets.all(22),
                                  ),
                                ),
                                const SizedBox(height: 10),
                                const Text('Decline',
                                    style: TextStyle(
                                        color: AppTheme.textSecondary,
                                        fontSize: 12)),
                              ],
                            ),
                            const SizedBox(width: 80),
                            // Answer
                            Column(
                              children: [
                                Container(
                                  decoration: BoxDecoration(
                                    color: AppTheme.success
                                        .withValues(alpha: 0.9),
                                    shape: BoxShape.circle,
                                    boxShadow: [
                                      BoxShadow(
                                        color: AppTheme.success
                                            .withValues(alpha: 0.3),
                                        blurRadius: 16,
                                        spreadRadius: 2,
                                      ),
                                    ],
                                  ),
                                  child: IconButton(
                                    icon: Icon(
                                      widget.callData.isVideoCall
                                          ? Icons.videocam_rounded
                                          : Icons.phone_rounded,
                                      color: Colors.white,
                                      size: 28,
                                    ),
                                    onPressed: _acceptCall,
                                    iconSize: 28,
                                    padding: const EdgeInsets.all(22),
                                  ),
                                ),
                                const SizedBox(height: 10),
                                const Text('Accept',
                                    style: TextStyle(
                                        color: AppTheme.textSecondary,
                                        fontSize: 12)),
                              ],
                            ),
                          ],
                        ),
                      ),
                    // Connected controls
                    if (_callState == CallState.connected)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 48),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            // Mute
                            _CallControlButton(
                              icon: _isMuted
                                  ? Icons.mic_off_rounded
                                  : Icons.mic_rounded,
                              label: _isMuted ? 'Unmute' : 'Mute',
                              color: _isMuted
                                  ? AppTheme.primaryIndigo
                                  : Colors.white70,
                              backgroundColor: _isMuted
                                  ? AppTheme.primaryIndigo
                                      .withValues(alpha: 0.2)
                                  : Colors.white12,
                              onPressed: () {
                                setState(() {
                                  _isMuted = !_isMuted;
                                });
                              },
                            ),
                            // Video toggle
                            if (widget.callData.isVideoCall)
                              _CallControlButton(
                                icon: _isVideoEnabled
                                    ? Icons.videocam_rounded
                                    : Icons.videocam_off_rounded,
                                label: _isVideoEnabled
                                    ? 'Video On'
                                    : 'Video Off',
                                color: _isVideoEnabled
                                    ? Colors.white70
                                    : AppTheme.primaryIndigo,
                                backgroundColor: _isVideoEnabled
                                    ? Colors.white12
                                    : AppTheme.primaryIndigo
                                        .withValues(alpha: 0.2),
                                onPressed: () {
                                  setState(() {
                                    _isVideoEnabled = !_isVideoEnabled;
                                  });
                                },
                              ),
                            // Speaker
                            _CallControlButton(
                              icon: _isSpeakerOff
                                  ? Icons.volume_up_rounded
                                  : Icons.volume_off_rounded,
                              label: _isSpeakerOff
                                  ? 'Speaker'
                                  : 'Mute',
                              color: _isSpeakerOff
                                  ? Colors.white70
                                  : AppTheme.primaryIndigo,
                              backgroundColor: _isSpeakerOff
                                  ? Colors.white12
                                  : AppTheme.primaryIndigo
                                      .withValues(alpha: 0.2),
                              onPressed: () {
                                setState(() {
                                  _isSpeakerOff = !_isSpeakerOff;
                                });
                              },
                            ),
                            // End call
                            _CallControlButton(
                              icon: Icons.call_end_rounded,
                              label: 'End',
                              color: Colors.white,
                              backgroundColor: AppTheme.error,
                              onPressed: _endCall,
                              isDestructive: true,
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
        ),
      ),
    );
  }
}

class _CallControlButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final Color backgroundColor;
  final VoidCallback onPressed;
  final bool isDestructive;

  const _CallControlButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.backgroundColor,
    required this.onPressed,
    this.isDestructive = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          decoration: BoxDecoration(
            color: backgroundColor,
            shape: BoxShape.circle,
            boxShadow: isDestructive
                ? [
                    BoxShadow(
                      color: AppTheme.error.withValues(alpha: 0.3),
                      blurRadius: 16,
                      spreadRadius: 2,
                    ),
                  ]
                : null,
          ),
          child: IconButton(
            icon: Icon(icon, color: color, size: 26),
            onPressed: onPressed,
            padding: const EdgeInsets.all(18),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: const TextStyle(
            color: AppTheme.textSecondary,
            fontSize: 11,
          ),
        ),
      ],
    );
  }
}
