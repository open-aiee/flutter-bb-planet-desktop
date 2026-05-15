import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/config/app_config.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../workspace/presentation/chat_ops_workspace_screen.dart';
import '../application/operator_auth_controller.dart';

class OperatorLoginScreen extends ConsumerStatefulWidget {
  const OperatorLoginScreen({super.key});

  static const routePath = '/login';

  @override
  ConsumerState<OperatorLoginScreen> createState() =>
      _OperatorLoginScreenState();
}

class _OperatorLoginScreenState extends ConsumerState<OperatorLoginScreen> {
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      body: Container(
        color: const Color(0xfff0f2f5),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1020),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(3),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.08),
                    blurRadius: 28,
                    offset: const Offset(0, 12),
                  ),
                ],
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(68, 58, 34, 44),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      flex: 7,
                      child: Transform.translate(
                        offset: const Offset(0, -30),
                        child: const _QrLoginInstructions(),
                      ),
                    ),
                    const SizedBox(width: 150),
                    Expanded(
                      flex: 4,
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: Transform.translate(
                          offset: const Offset(-60, 0),
                          child: _DesktopQrPanel(
                            developmentEntry: appConfig.allowAuthBypass
                                ? TextButton(
                                    onPressed: _bypass,
                                    child: Text(l10n.devEnterWorkspace),
                                  )
                                : null,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _bypass() {
    ref.read(operatorAuthControllerProvider.notifier).bypassForDevelopment();
    context.go(ChatOpsWorkspaceScreen.routePath);
  }
}

class _QrLoginInstructions extends StatelessWidget {
  const _QrLoginInstructions();

  @override
  Widget build(BuildContext context) {
    return const Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'To use Desktop on your computer:',
          style: TextStyle(
            color: Color(0xff111b21),
            fontSize: 28,
            height: 36 / 28,
            fontWeight: FontWeight.w300,
          ),
        ),
        SizedBox(height: 34),
        _LoginStep(index: 1, text: 'Open App on your phone'),
        _LoginStep(index: 2, text: 'Find the top right corner of my page'),
        _LoginStep(index: 3, text: 'Tap on QR'),
        _LoginStep(
          index: 4,
          text: 'Point your phone to this screen to capture the code',
        ),
      ],
    );
  }
}

class _LoginStep extends StatelessWidget {
  const _LoginStep({required this.index, required this.text});

  final int index;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 26,
          child: Text(
            '$index.',
            style: const TextStyle(
              color: Color(0xff3b4a54),
              fontSize: 18,
              height: 32 / 18,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              color: Color(0xff3b4a54),
              fontSize: 18,
              height: 32 / 18,
              fontWeight: FontWeight.w400,
            ),
          ),
        ),
      ],
    );
  }
}

class _DesktopQrPanel extends StatelessWidget {
  const _DesktopQrPanel({this.developmentEntry});

  final Widget? developmentEntry;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 286,
          height: 286,
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(color: const Color(0xffe5e9ec)),
          ),
          child: const CustomPaint(painter: _QrCodePlaceholderPainter()),
        ),
        const SizedBox(height: 18),
        const Text(
          'Scan to sign in',
          style: TextStyle(
            color: Color(0xff54656f),
            fontSize: 14,
            height: 20 / 14,
            fontWeight: FontWeight.w500,
          ),
        ),
        if (developmentEntry != null) ...[
          const SizedBox(height: 8),
          developmentEntry!,
        ],
      ],
    );
  }
}

class _QrCodePlaceholderPainter extends CustomPainter {
  const _QrCodePlaceholderPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final cell = size.width / 29;
    final paint = Paint()..color = const Color(0xff111b21);
    final lightPaint = Paint()..color = const Color(0xffdce5e7);

    canvas.drawRect(Offset.zero & size, Paint()..color = Colors.white);
    void drawFinder(int x, int y) {
      final rect = Rect.fromLTWH(x * cell, y * cell, cell * 7, cell * 7);
      canvas.drawRect(rect, paint);
      canvas.drawRect(rect.deflate(cell), Paint()..color = Colors.white);
      canvas.drawRect(rect.deflate(cell * 2), paint);
    }

    drawFinder(0, 0);
    drawFinder(22, 0);
    drawFinder(0, 22);

    for (var y = 0; y < 29; y += 1) {
      for (var x = 0; x < 29; x += 1) {
        final inFinder =
            (x < 8 && y < 8) || (x > 20 && y < 8) || (x < 8 && y > 20);
        if (inFinder) {
          continue;
        }
        final filled =
            ((x * 11 + y * 7) % 5 == 0) ||
            ((x * 3 + y * 13) % 11 == 0) ||
            (x > 10 && y > 10 && (x + y) % 7 == 0);
        if (filled) {
          canvas.drawRect(
            Rect.fromLTWH(x * cell, y * cell, cell * 0.92, cell * 0.92),
            paint,
          );
        } else if ((x + y) % 17 == 0) {
          canvas.drawRect(
            Rect.fromLTWH(x * cell, y * cell, cell * 0.8, cell * 0.8),
            lightPaint,
          );
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
