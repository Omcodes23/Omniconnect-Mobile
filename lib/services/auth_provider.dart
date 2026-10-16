import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/api_service.dart';
import '../models/user.dart';

final apiServiceProvider = Provider<ApiService>((ref) => ApiService());

final authStateProvider = NotifierProvider<AuthNotifier, AuthState>(AuthNotifier.new);

enum AuthStatus { unknown, authenticated, unauthenticated }

class AuthState {
  final AuthStatus status;
  final UserDto? user;
  final String? error;
  final bool isLoading;

  const AuthState({
    this.status = AuthStatus.unknown,
    this.user,
    this.error,
    this.isLoading = false,
  });

  AuthState copyWith({
    AuthStatus? status,
    UserDto? user,
    String? error,
    bool? isLoading,
  }) {
    return AuthState(
      status: status ?? this.status,
      user: user ?? this.user,
      error: error,
      isLoading: isLoading ?? this.isLoading,
    );
  }
}

class AuthNotifier extends Notifier<AuthState> {
  @override
  AuthState build() => const AuthState();

  Future<void> login(String email, String password) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final api = ref.read(apiServiceProvider);
      final auth = await api.login(email, password);
      state = AuthState(
        status: AuthStatus.authenticated,
        user: auth.user,
      );
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: e.toString(),
        status: AuthStatus.unauthenticated,
      );
    }
  }

  Future<void> register(
      String username, String email, String password, String displayName) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final api = ref.read(apiServiceProvider);
      final auth = await api.register(username, email, password, displayName);
      state = AuthState(
        status: AuthStatus.authenticated,
        user: auth.user,
      );
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: e.toString(),
        status: AuthStatus.unauthenticated,
      );
    }
  }

  Future<void> logout() async {
    final api = ref.read(apiServiceProvider);
    await api.logout();
    state = const AuthState(status: AuthStatus.unauthenticated);
  }
}
