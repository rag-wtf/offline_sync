/// Constants for RAG (Retrieval-Augmented Generation) system configuration
///
/// These values control token budget allocation, chunking behavior, and
/// search relevance scoring. Extracted from hardcoded values to improve
/// maintainability and tunability.
class RagConstants {
  // Token Budget Allocation Ratios (for prompt construction)

  /// Percentage of available tokens reserved for model output (25%)
  static const double outputReserveRatio = 0.25;

  /// Percentage of prompt budget allocated to retrieved context (55%)
  static const double contextBudgetRatio = 0.55;

  /// Percentage of prompt budget allocated to conversation history (35%)
  static const double historyBudgetRatio = 0.35;

  // Chunking Configuration

  /// Maximum characters per chunk for embedding generation (~100 tokens)
  ///
  /// This provides a safe margin under the 254 token limit for the embedding
  /// model, accounting for markdown/code that may tokenize at 2-3x rate.
  static const int maxCharsPerChunk = 500;

  // Reranking Configuration

  /// Maximum characters to send to reranking model (truncate longer content)
  static const int maxCharsForReranking = 500;

  // Search Ranking Configuration

  /// Reciprocal Rank Fusion (RRF) constant for hybrid search scoring
  ///
  /// Higher values (e.g., 60) dampen the effect of lower-ranked results.
  /// See: https://plg.uwaterloo.ca/~gvcormac/cormacksigir09-rrf.pdf
  static const double rrfConstant = 60;
}
