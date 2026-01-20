# Test Documents

This directory contains sample documents for testing the RAG system's document ingestion and processing capabilities.

## Test Files

### Supported Formats

| File | Format | Size | Description | Purpose |
|------|--------|------|-------------|---------|
| `sample_small.pdf` | PDF | 2.3 KB | Single-page PDF with basic text content | Test basic PDF parsing |
| `sample_large.pdf` | PDF | 7.7 MB | 1000-page PDF with random text | Test large file handling and performance |
| `sample_document.docx` | DOCX | 37 KB | Word document with rich formatting | Test DOCX parsing and structure extraction |
| `sample_book.epub` | EPUB | 4.0 KB | Multi-chapter ebook | Test EPUB parsing and chapter handling |
| `sample_small.md` | Markdown | 821 B | Markdown with various elements | Test markdown parsing |
| `sample_text.txt` | Plain Text | 1.2 KB | Simple text file | Test plain text ingestion |

### Unsupported Formats

| File | Format | Size | Description | Purpose |
|------|--------|------|-------------|---------|
| `sample_spreadsheet.xlsx` | Excel | 5.0 KB | Excel spreadsheet with sample data | Test error handling for unsupported formats |

## Testing Scenarios

### 1. Basic Ingestion
- **Files**: `sample_small.pdf`, `sample_text.txt`, `sample_small.md`
- **Expected**: All files should be successfully ingested and indexed
- **Validation**: Search for content from each file

### 2. Large File Handling
- **Files**: `sample_large.pdf`
- **Expected**: System should handle large files without crashing
- **Validation**: Monitor memory usage, check chunking behavior

### 3. Format Support
- **Files**: `sample_document.docx`, `sample_book.epub`
- **Expected**: Proper text extraction from formatted documents
- **Validation**: Verify structure preservation and content accuracy

### 4. Error Handling
- **Files**: `sample_spreadsheet.xlsx`
- **Expected**: Graceful error handling with clear error messages
- **Validation**: Check that unsupported format is properly rejected

## File Details

### sample_small.pdf
- **Pages**: 1
- **Content**: Introduction to PDF processing with sections on features and testing
- **Key phrases**: "PDF test document", "document ingestion", "semantic search"

### sample_large.pdf
- **Pages**: 1000
- **Content**: Random text across 1000 pages (uncompressed for size)
- **Key phrases**: Random alphanumeric content
- **Note**: Created without compression to achieve >5MB size

### sample_document.docx
- **Sections**: Introduction, Document Structure, Testing Objectives, Sample Table, Conclusion
- **Features**: Headings, lists, tables, formatted text
- **Key phrases**: "DOCX test document", "rich formatting", "document parser"

### sample_book.epub
- **Chapters**: 4 (Introduction, Chapter 1, Chapter 2, Conclusion)
- **Content**: Information about EPUB processing and testing
- **Key phrases**: "EPUB document", "electronic book", "chapter structure"

### sample_small.md
- **Elements**: Headers, lists, code blocks, tables, links, emphasis
- **Content**: Markdown syntax examples and testing information
- **Key phrases**: "markdown file", "document processing", "test parsing"

### sample_text.txt
- **Format**: Plain ASCII text with section headers
- **Content**: Lorem ipsum and technical information
- **Key phrases**: "plain text file", "UTF-8 format", "pangram"

### sample_spreadsheet.xlsx
- **Sheets**: 1 (Test Data)
- **Content**: Table with ID, Name, Category, Status columns
- **Purpose**: Verify that unsupported formats are properly rejected

## Usage

1. **Manual Testing**: Import these files through the document library UI
2. **Automated Testing**: Use these files in integration tests
3. **Performance Testing**: Use `sample_large.pdf` for stress testing
4. **Error Testing**: Use `sample_spreadsheet.xlsx` to verify error handling

## Regeneration

If you need to regenerate these test files, refer to the Python scripts used to create them (available in the conversation history or can be recreated using the reportlab, python-docx, ebooklib, and openpyxl libraries).
