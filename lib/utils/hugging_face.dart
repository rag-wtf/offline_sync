/// Derives the Hugging Face repository page from a model file download [url].
///
/// Extracts the first two path segments (owner/repo) from a Hugging Face URL.
/// Returns [url] unmodified if an owner/repository pair cannot be extracted.
String deriveHuggingFaceRepoPage(String url) {
  final uri = Uri.parse(url);
  final segments = uri.pathSegments;
  if (uri.host == 'huggingface.co' && segments.length >= 2) {
    return 'https://huggingface.co/${segments[0]}/${segments[1]}';
  }
  return url;
}
