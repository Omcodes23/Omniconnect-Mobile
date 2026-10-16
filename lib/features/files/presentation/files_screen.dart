import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/app_theme.dart';
import '../../../services/auth_provider.dart';

class FileItem {
  final String id;
  final String fileName;
  final int fileSize;
  final String fileUrl;
  final String uploadedBy;
  final String? mimeType;
  final DateTime uploadedAt;

  FileItem({
    required this.id,
    required this.fileName,
    required this.fileSize,
    required this.fileUrl,
    required this.uploadedBy,
    this.mimeType,
    required this.uploadedAt,
  });

  factory FileItem.fromJson(Map<String, dynamic> json) => FileItem(
        id: json['id']?.toString() ?? '',
        fileName: json['fileName'] ?? '',
        fileSize: json['fileSize'] ?? 0,
        fileUrl: json['fileUrl'] ?? '',
        uploadedBy: json['uploadedBy'] ?? '',
        mimeType: json['mimeType'],
        uploadedAt: DateTime.tryParse(json['uploadedAt'] ?? '') ?? DateTime.now(),
      );
}

class FilesState {
  final List<FileItem> files;
  final bool isLoading;
  final String? error;

  const FilesState({
    this.files = const [],
    this.isLoading = false,
    this.error,
  });

  FilesState copyWith({
    List<FileItem>? files,
    bool? isLoading,
    String? error,
  }) {
    return FilesState(
      files: files ?? this.files,
      isLoading: isLoading ?? this.isLoading,
      error: error,
    );
  }
}

class FilesNotifier extends Notifier<FilesState> {
  @override
  FilesState build() => const FilesState();

  Future<void> loadFiles() async {
    state = state.copyWith(isLoading: true);
    try {
      final api = ref.read(apiServiceProvider);
      final data = await api.get('/api/files');
      final files = data.map((e) => FileItem.fromJson(e as Map<String, dynamic>)).toList();
      state = state.copyWith(files: files, isLoading: false);
    } catch (e) {
      state = state.copyWith(isLoading: false, error: 'Failed to load files: $e');
    }
  }

  Future<void> deleteFile(String id) async {
    try {
      final api = ref.read(apiServiceProvider);
      await api.post('/api/files/$id/delete', null);
      state = state.copyWith(
        files: state.files.where((f) => f.id != id).toList(),
      );
    } catch (e) {
      state = state.copyWith(error: 'Failed to delete file: $e');
    }
  }
}

final filesProvider = NotifierProvider<FilesNotifier, FilesState>(FilesNotifier.new);

class FilesScreen extends ConsumerStatefulWidget {
  const FilesScreen({super.key});

  @override
  ConsumerState<FilesScreen> createState() => _FilesScreenState();
}

class _FilesScreenState extends ConsumerState<FilesScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(filesProvider.notifier).loadFiles();
    });
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  IconData _getFileIcon(String? mimeType, String fileName) {
    final ext = fileName.split('.').last.toLowerCase();
    switch (ext) {
      case 'pdf':
        return Icons.picture_as_pdf;
      case 'jpg':
      case 'jpeg':
      case 'png':
      case 'gif':
      case 'webp':
        return Icons.image;
      case 'mp4':
      case 'mov':
      case 'avi':
        return Icons.videocam;
      case 'mp3':
      case 'wav':
      case 'ogg':
        return Icons.audiotrack;
      case 'zip':
      case 'rar':
      case 'tar':
      case 'gz':
        return Icons.folder_zip;
      default:
        return Icons.insert_drive_file;
    }
  }

  Color _getFileColor(String? mimeType, String fileName) {
    final ext = fileName.split('.').last.toLowerCase();
    switch (ext) {
      case 'pdf':
        return Colors.red;
      case 'jpg':
      case 'jpeg':
      case 'png':
      case 'gif':
      case 'webp':
        return Colors.green;
      case 'mp4':
      case 'mov':
      case 'avi':
        return Colors.blue;
      case 'mp3':
      case 'wav':
      case 'ogg':
        return Colors.purple;
      case 'zip':
      case 'rar':
      case 'tar':
      case 'gz':
        return Colors.orange;
      default:
        return AppTheme.primaryIndigo;
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(filesProvider);

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text(
          'Files',
          style: TextStyle(color: AppTheme.textPrimary),
        ),
        backgroundColor: AppTheme.surface,
        elevation: 0,
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 4),
            decoration: BoxDecoration(
              color: AppTheme.primaryIndigo.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: IconButton(
              icon: const Icon(Icons.upload_file_rounded,
                  color: AppTheme.primaryIndigo),
              onPressed: () {},
            ),
          ),
        ],
      ),
      body: state.isLoading
          ? const Center(
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: AppTheme.primaryIndigo,
              ),
            )
          : state.files.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.cloud_upload_outlined,
                          size: 64,
                          color: AppTheme.textMuted.withValues(alpha: 0.5)),
                      const SizedBox(height: 16),
                      const Text(
                        'No files yet',
                        style: TextStyle(
                            color: AppTheme.textMuted, fontSize: 16),
                      ),
                      const SizedBox(height: 16),
                      Container(
                        decoration: BoxDecoration(
                          gradient: AppTheme.linearGradient(),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: ElevatedButton.icon(
                          onPressed: () {},
                          icon: const Icon(Icons.upload_file_rounded,
                              size: 18, color: Colors.white),
                          label: const Text('Upload File',
                              style: TextStyle(color: Colors.white)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.transparent,
                            shadowColor: Colors.transparent,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 20, vertical: 12),
                          ),
                        ),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(8),
                  itemCount: state.files.length,
                  itemBuilder: (context, index) {
                    final file = state.files[index];
                    final dateStr =
                        DateFormat('MMM d, yyyy HH:mm').format(file.uploadedAt);
                    return Container(
                      margin: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppTheme.surface,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            color: Colors.white.withValues(alpha: 0.06)),
                      ),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor:
                              _getFileColor(file.mimeType, file.fileName)
                                  .withValues(alpha: 0.12),
                          child: Icon(
                            _getFileIcon(file.mimeType, file.fileName),
                            color:
                                _getFileColor(file.mimeType, file.fileName),
                          ),
                        ),
                        title: Text(
                          file.fileName,
                          style: const TextStyle(
                            color: AppTheme.textPrimary,
                            fontWeight: FontWeight.w500,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          '${_formatSize(file.fileSize)} - $dateStr',
                          style: const TextStyle(
                            color: AppTheme.textMuted,
                            fontSize: 12,
                          ),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              decoration: BoxDecoration(
                                color: AppTheme.success.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: IconButton(
                                icon: const Icon(Icons.download_rounded,
                                    color: AppTheme.success, size: 20),
                                onPressed: () {},
                              ),
                            ),
                            Container(
                              decoration: BoxDecoration(
                                color: AppTheme.error.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: IconButton(
                                icon: const Icon(Icons.delete_rounded,
                                    color: AppTheme.error, size: 20),
                                onPressed: () {
                                  showDialog(
                                    context: context,
                                    builder: (ctx) => AlertDialog(
                                      backgroundColor: AppTheme.surface,
                                      title: const Text(
                                        'Delete File',
                                        style: TextStyle(
                                            color: AppTheme.textPrimary),
                                      ),
                                      content: Text(
                                          'Delete "${file.fileName}"?',
                                          style: const TextStyle(
                                              color: AppTheme.textSecondary)),
                                      actions: [
                                        TextButton(
                                          onPressed: () =>
                                              Navigator.pop(ctx),
                                          child: const Text('Cancel'),
                                        ),
                                        TextButton(
                                          onPressed: () {
                                            ref
                                                .read(filesProvider.notifier)
                                                .deleteFile(file.id);
                                            Navigator.pop(ctx);
                                          },
                                          child: const Text(
                                            'Delete',
                                            style: TextStyle(
                                                color: AppTheme.error),
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                },
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}
