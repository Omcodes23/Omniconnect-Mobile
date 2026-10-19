/// The curated local-model catalog.
///
/// IMPORTANT: this is a mirror of
/// `Desktop-Application/src/Shared/Models/ModelCatalog.cs`. The two must stay
/// in sync — same ids, file names, sizes, URLs and context lengths — so a
/// conversation started on one platform maps to the same model on the other.
///
/// The mobile client keeps its own copy (rather than asking the desktop
/// backend) because the whole point of the embedded runtime is that chat works
/// with the backend offline. Downloading a model is the only network step, and
/// it goes straight to the HuggingFace CDN over plain HTTPS: no auth, no API
/// key, no OmniConnect server involved.
library;

class ModelCatalogEntry {
  final String id;
  final String displayName;
  final String description;
  final String fileName;
  final String downloadUrl;
  final int sizeBytes;
  final String quantization;
  final int contextLength;
  final String family;

  const ModelCatalogEntry({
    required this.id,
    required this.displayName,
    required this.description,
    required this.fileName,
    required this.downloadUrl,
    required this.sizeBytes,
    required this.quantization,
    required this.contextLength,
    required this.family,
  });

  String get sizeLabel => ModelCatalog.formatSize(sizeBytes);
}

class ModelCatalog {
  ModelCatalog._();

  static const String _hf = 'https://huggingface.co';

  static const List<ModelCatalogEntry> all = [
    ModelCatalogEntry(
      id: 'qwen2.5-0.5b-instruct-q4km',
      displayName: 'Qwen2.5 0.5B (Starter)',
      description:
          'Tiny and fast. Great first download for older phones and laptops.',
      fileName: 'qwen2.5-0.5b-instruct-q4_k_m.gguf',
      downloadUrl:
          '$_hf/Qwen/Qwen2.5-0.5B-Instruct-GGUF/resolve/main/qwen2.5-0.5b-instruct-q4_k_m.gguf',
      sizeBytes: 397808000,
      quantization: 'Q4_K_M',
      contextLength: 4096,
      family: 'Qwen2.5',
    ),
    ModelCatalogEntry(
      id: 'qwen2.5-1.5b-instruct-q4km',
      displayName: 'Qwen2.5 1.5B',
      description: 'Balanced quality and speed. Recommended default.',
      fileName: 'qwen2.5-1.5b-instruct-q4_k_m.gguf',
      downloadUrl:
          '$_hf/Qwen/Qwen2.5-1.5B-Instruct-GGUF/resolve/main/qwen2.5-1.5b-instruct-q4_k_m.gguf',
      sizeBytes: 1117320000,
      quantization: 'Q4_K_M',
      contextLength: 4096,
      family: 'Qwen2.5',
    ),
    ModelCatalogEntry(
      id: 'llama-3.2-1b-instruct-q4km',
      displayName: 'Llama 3.2 1B',
      description: "Meta's small instruction model. Solid general-purpose chat.",
      fileName: 'Llama-3.2-1B-Instruct-Q4_K_M.gguf',
      downloadUrl:
          '$_hf/bartowski/Llama-3.2-1B-Instruct-GGUF/resolve/main/Llama-3.2-1B-Instruct-Q4_K_M.gguf',
      sizeBytes: 807694000,
      quantization: 'Q4_K_M',
      contextLength: 8192,
      family: 'Llama 3.2',
    ),
    ModelCatalogEntry(
      id: 'llama-3.2-3b-instruct-q4km',
      displayName: 'Llama 3.2 3B',
      description: 'Noticeably smarter, needs ~3 GB RAM free.',
      fileName: 'Llama-3.2-3B-Instruct-Q4_K_M.gguf',
      downloadUrl:
          '$_hf/bartowski/Llama-3.2-3B-Instruct-GGUF/resolve/main/Llama-3.2-3B-Instruct-Q4_K_M.gguf',
      sizeBytes: 2019388000,
      quantization: 'Q4_K_M',
      contextLength: 8192,
      family: 'Llama 3.2',
    ),
    ModelCatalogEntry(
      id: 'phi-3.5-mini-instruct-q4km',
      displayName: 'Phi-3.5 Mini',
      description: 'Strong reasoning for its size. Best on desktops.',
      fileName: 'Phi-3.5-mini-instruct-Q4_K_M.gguf',
      downloadUrl:
          '$_hf/bartowski/Phi-3.5-mini-instruct-GGUF/resolve/main/Phi-3.5-mini-instruct-Q4_K_M.gguf',
      sizeBytes: 2393233000,
      quantization: 'Q4_K_M',
      contextLength: 4096,
      family: 'Phi-3.5',
    ),
    ModelCatalogEntry(
      id: 'gemma-2-2b-it-q4km',
      displayName: 'Gemma 2 2B',
      description:
          "Google's compact chat model. Friendly, conversational tone.",
      fileName: 'gemma-2-2b-it-Q4_K_M.gguf',
      downloadUrl:
          '$_hf/bartowski/gemma-2-2b-it-GGUF/resolve/main/gemma-2-2b-it-Q4_K_M.gguf',
      sizeBytes: 1711902000,
      quantization: 'Q4_K_M',
      contextLength: 8192,
      family: 'Gemma 2',
    ),
  ];

  static ModelCatalogEntry? find(String? id) {
    if (id == null || id.trim().isEmpty) return null;
    for (final m in all) {
      if (m.id.toLowerCase() == id.toLowerCase()) return m;
    }
    return null;
  }

  /// The model suggested when nothing is downloaded yet.
  static ModelCatalogEntry get defaultModel => find('qwen2.5-1.5b-instruct-q4km')!;

  /// Human-friendly byte formatting, identical to `ModelCatalog.FormatSize`.
  static String formatSize(int bytes) {
    if (bytes <= 0) return '0 B';
    const units = ['B', 'KB', 'MB', 'GB', 'TB'];
    double value = bytes.toDouble();
    int unit = 0;
    while (value >= 1024 && unit < units.length - 1) {
      value /= 1024;
      unit++;
    }
    return unit == 0
        ? '${value.toStringAsFixed(0)} ${units[unit]}'
        : '${value.toStringAsFixed(1)} ${units[unit]}';
  }
}
