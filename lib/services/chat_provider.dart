import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/user.dart';
import '../models/community.dart';
import '../models/message.dart';
import '../models/friend.dart';
import 'auth_provider.dart';

class ChatState {
  final List<UserDto> friends;
  final List<CommunityDto> communities;
  final List<ChannelDto> channels;
  final List<MessageDto> messages;
  final bool isLoading;
  final String? error;

  const ChatState({
    this.friends = const [],
    this.communities = const [],
    this.channels = const [],
    this.messages = const [],
    this.isLoading = false,
    this.error,
  });

  ChatState copyWith({
    List<UserDto>? friends,
    List<CommunityDto>? communities,
    List<ChannelDto>? channels,
    List<MessageDto>? messages,
    bool? isLoading,
    String? error,
  }) {
    return ChatState(
      friends: friends ?? this.friends,
      communities: communities ?? this.communities,
      channels: channels ?? this.channels,
      messages: messages ?? this.messages,
      isLoading: isLoading ?? this.isLoading,
      error: error,
    );
  }
}

class ChatNotifier extends Notifier<ChatState> {
  @override
  ChatState build() => const ChatState();

  Future<void> loadFriends() async {
    try {
      final api = ref.read(apiServiceProvider);
      final data = await api.get('/api/friends');
      final myUserId = ref.read(authStateProvider).user?.id;
      final List<UserDto> friends = [];
      for (final item in data) {
        if (item is Map<String, dynamic>) {
          final f = FriendRequestDto.fromJson(item);
          final isRequester = f.requesterId == myUserId;
          friends.add(UserDto(
            id: isRequester ? f.addresseeId : f.requesterId,
            username: isRequester ? f.addresseeName : f.requesterName,
            displayName: isRequester ? f.addresseeName : f.requesterName,
            avatarUrl: isRequester ? f.addresseeAvatar : f.requesterAvatar,
            status: 'Online',
          ));
        }
      }
      state = state.copyWith(friends: friends);
    } catch (e) {
      state = state.copyWith(error: 'Failed to load friends: $e');
    }
  }

  Future<void> loadCommunities() async {
    try {
      final api = ref.read(apiServiceProvider);
      final data = await api.get('/api/communities');
      final communities =
          data.map((e) => CommunityDto.fromJson(e as Map<String, dynamic>)).toList();
      state = state.copyWith(communities: communities);
    } catch (e) {
      state = state.copyWith(error: 'Failed to load communities: $e');
    }
  }

  Future<void> loadChannels(String communityId) async {
    try {
      final api = ref.read(apiServiceProvider);
      final data = await api.get('/api/communities/$communityId/channels');
      final channels =
          data.map((e) => ChannelDto.fromJson(e as Map<String, dynamic>)).toList();
      state = state.copyWith(channels: channels);
    } catch (e) {
      state = state.copyWith(error: 'Failed to load channels: $e');
    }
  }

  Future<void> loadMessages(String conversationId) async {
    state = state.copyWith(isLoading: true);
    try {
      final api = ref.read(apiServiceProvider);
      final data = await api.get('/api/messages/conversation/$conversationId');
      final messages =
          data.map((e) => MessageDto.fromJson(e as Map<String, dynamic>)).toList();
      state = state.copyWith(messages: messages, isLoading: false);
    } catch (e) {
      state = state.copyWith(error: 'Failed to load messages: $e', isLoading: false);
    }
  }

  Future<void> loadChannelMessages(String communityId, String channelId) async {
    state = state.copyWith(isLoading: true);
    try {
      final api = ref.read(apiServiceProvider);
      final data = await api.get('/api/messages/channel/$communityId/$channelId');
      final messages =
          data.map((e) => MessageDto.fromJson(e as Map<String, dynamic>)).toList();
      state = state.copyWith(messages: messages, isLoading: false);
    } catch (e) {
      state = state.copyWith(error: 'Failed to load channel messages: $e', isLoading: false);
    }
  }

  Future<MessageDto?> sendMessage({
    String? receiverId,
    String? communityId,
    String? channelId,
    required String content,
    String type = 'Text',
    String? mediaUrl,
    int? fileSize,
    String? fileName,
    String? replyToId,
  }) async {
    try {
      final api = ref.read(apiServiceProvider);
      final request = SendMessageRequest(
        receiverId: receiverId,
        communityId: communityId,
        channelId: channelId,
        type: type,
        content: content,
        mediaUrl: mediaUrl,
        fileSize: fileSize,
        fileName: fileName,
        replyToId: replyToId,
      );
      final result = await api.post('/api/messages', request.toJson());
      final message = MessageDto.fromJson(result);
      if (!state.messages.any((m) => m.id == message.id)) {
        state = state.copyWith(messages: [...state.messages, message]);
      }
      return message;
    } catch (e) {
      state = state.copyWith(error: 'Failed to send message: $e');
      return null;
    }
  }

  void addReceivedMessage(MessageDto message) {
    if (!state.messages.any((m) => m.id == message.id)) {
      state = state.copyWith(messages: [...state.messages, message]);
    }
  }

  Future<void> ensureFriend(String userId) async {
    try {
      final api = ref.read(apiServiceProvider);
      await api.ensureFriend(userId);
      await loadFriends();
    } catch (_) {}
  }

  Future<void> loadAll() async {
    await Future.wait([loadFriends(), loadCommunities()]);
  }
}

final chatProvider = NotifierProvider<ChatNotifier, ChatState>(ChatNotifier.new);