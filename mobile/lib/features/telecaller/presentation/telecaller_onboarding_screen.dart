import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/network/app_provider.dart';
import '../data/telecaller_recording_setup.dart';

/// First-run: enable phone call recording → test call → link recordings folder.
class TelecallerOnboardingScreen extends StatefulWidget {
  const TelecallerOnboardingScreen({super.key, required this.onComplete});

  final VoidCallback onComplete;

  @override
  State<TelecallerOnboardingScreen> createState() =>
      _TelecallerOnboardingScreenState();
}

class _TelecallerOnboardingScreenState extends State<TelecallerOnboardingScreen>
    with WidgetsBindingObserver {
  int _step = 0;
  bool _awaitingTestCallReturn = false;
  String? _linkedFolder;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(TelecallerRecordingSetup.load().then((_) {
      if (!mounted) return;
      setState(() {
        _linkedFolder = TelecallerRecordingSetup.folderLabel ??
            TelecallerRecordingSetup.folderPath;
      });
    }));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed &&
        _awaitingTestCallReturn &&
        _step == 1 &&
        mounted) {
      _awaitingTestCallReturn = false;
      setState(() => _step = 2);
    }
  }

  String? get _testPhone {
    final phone = context.read<AppProvider>().phone?.trim();
    if (phone != null && phone.isNotEmpty) return phone;
    return null;
  }

  void _toast(String msg, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: error ? Colors.red.shade700 : const Color(0xFF1E3A8A),
      ),
    );
  }

  Future<void> _launchTestCall() async {
    final phone = _testPhone;
    if (phone == null) {
      _toast('Add your phone number on your user profile first', error: true);
      return;
    }
    final digits = phone.replaceAll(RegExp(r'[^\d+]'), '');
    final launched = await launchUrl(
      Uri(scheme: 'tel', path: digits),
      mode: LaunchMode.externalApplication,
    );
    if (!launched) {
      _toast('Could not open phone app', error: true);
      return;
    }
    _awaitingTestCallReturn = true;
  }

  Future<void> _pickRecordingFolder() async {
    try {
      final path = await FilePicker.platform.getDirectoryPath(
        dialogTitle: 'Choose call recordings folder',
      );
      if (path == null || path.isEmpty) return;
      await TelecallerRecordingSetup.setFolderPath(path: path);
      if (!mounted) return;
      setState(() => _linkedFolder = TelecallerRecordingSetup.folderLabel);
      _toast('Folder linked: ${TelecallerRecordingSetup.folderLabel}');
    } catch (e) {
      _toast('Could not link folder: $e', error: true);
    }
  }

  Future<void> _finish() async {
    if (!TelecallerRecordingSetup.hasLinkedFolder) {
      _toast(
        'Choose the folder where your phone saves call recordings',
        error: true,
      );
      return;
    }
    await TelecallerRecordingSetup.markComplete();
    widget.onComplete();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF2F7FB),
      appBar: AppBar(
        title: Text('Setup · ${_step + 1} of 3'),
        automaticallyImplyLeading: _step > 0,
        leading: _step > 0
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => setState(() => _step -= 1),
              )
            : null,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: _buildStep(),
        ),
      ),
    );
  }

  Widget _buildStep() {
    switch (_step) {
      case 0:
        return _stepCard(
          title: 'Turn on call recording',
          body:
              'Open your Phone app settings and enable automatic call recording so both sides of the conversation are saved.',
          tips: const [
            'Samsung: Phone → ⋮ → Settings → Call recording',
            'Xiaomi: Settings → System apps → Calls → Call recording',
            'Other: Phone app → Settings → search "call recording"',
          ],
          primaryLabel: 'Next',
          onPrimary: () => setState(() => _step = 1),
        );
      case 1:
        return _stepCard(
          title: 'Place a test call',
          body: _testPhone == null
              ? 'Add your mobile number on your user account first, then place a short test call to confirm recordings are saved.'
              : 'Call your number below, speak for a few seconds, hang up, then return here.',
          tips: [
            if (_testPhone != null) 'Your number: $_testPhone',
            'Make sure call recording is still enabled',
          ],
          primaryLabel: 'Start test call',
          onPrimary: _launchTestCall,
          secondaryLabel: 'I already called — continue',
          onSecondary: () => setState(() => _step = 2),
        );
      default:
        return _stepCard(
          title: 'Choose recordings folder',
          body:
              'Pick the folder where your phone saves call recordings. Future telecaller calls will upload from this folder automatically.',
          tips: [
            if (_linkedFolder != null) 'Linked: $_linkedFolder',
            'Vivo/Xiaomi: MIUI/sound_recorder/call_rec or Recordings',
            'Samsung: Call / Call recording',
          ],
          primaryLabel: 'Choose folder',
          onPrimary: _pickRecordingFolder,
          secondaryLabel: 'Finish setup',
          onSecondary: _finish,
        );
    }
  }

  Widget _stepCard({
    required String title,
    required String body,
    required List<String> tips,
    required String primaryLabel,
    required VoidCallback onPrimary,
    String? secondaryLabel,
    VoidCallback? onSecondary,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(title,
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
        const SizedBox(height: 12),
        Text(body, style: const TextStyle(fontSize: 15, height: 1.4)),
        const SizedBox(height: 16),
        ...tips.map(
          (t) => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.check_circle_outline,
                    size: 18, color: Color(0xFF1E3A8A)),
                const SizedBox(width: 8),
                Expanded(child: Text(t)),
              ],
            ),
          ),
        ),
        const Spacer(),
        FilledButton(onPressed: onPrimary, child: Text(primaryLabel)),
        if (secondaryLabel != null && onSecondary != null) ...[
          const SizedBox(height: 10),
          OutlinedButton(onPressed: onSecondary, child: Text(secondaryLabel)),
        ],
        if (!Platform.isAndroid && !Platform.isIOS)
          const Padding(
            padding: EdgeInsets.only(top: 12),
            child: Text(
              'Use an Android phone for OEM call recording + auto-upload.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.black54),
            ),
          ),
      ],
    );
  }
}
