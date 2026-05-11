import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/operator_auth/presentation/operator_login_screen.dart';
import '../../features/workspace/presentation/chat_ops_workspace_screen.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: OperatorLoginScreen.routePath,
    routes: [
      GoRoute(
        path: OperatorLoginScreen.routePath,
        builder: (context, state) => const OperatorLoginScreen(),
      ),
      GoRoute(
        path: ChatOpsWorkspaceScreen.routePath,
        builder: (context, state) => const ChatOpsWorkspaceScreen(),
      ),
    ],
  );
});
