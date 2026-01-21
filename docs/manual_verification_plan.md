# 📋 Manual Verification Plan

**Project:** `offline_sync` - On-device RAG with Flutter Gemma  
**Created:** 2026-01-20  
**Purpose:** Comprehensive manual testing checklist for all application features
**Prompt :** Carefully review the codebase in detail, think deeply and critically to create a comprehensive manual verification plan. Write the plan to docs/manual_verification_plan.md in a checklist format.
 
---

## 📑 Table of Contents

1. [Pre-requisites](#pre-requisites)
2. [Startup Flow](#1-startup-flow)
3. [Model Management](#2-model-management)
4. [Document Management](#3-document-management)
5. [Chat Functionality](#4-chat-functionality)
6. [RAG Quality Settings](#5-rag-quality-settings)
7. [Token Management Settings](#6-token-management-settings)
8. [Navigation & UI](#7-navigation--ui)
9. [Error Handling](#8-error-handling)
10. [Performance & Edge Cases](#9-performance--edge-cases)
11. [Cross-Platform Testing](#10-cross-platform-testing)
12. [Localization](#11-localization)
13. [Data Persistence](#12-data-persistence)

---

## 🤖 Automated Test Coverage Summary

This section documents which items from this manual verification plan are **already covered by automated tests** in the `test/` directory.

### Test Files Overview

| Test File | Coverage Area | Tests |
|-----------|--------------|-------|
| `auth_token_service_test.dart` | Token persistence | 6 tests |
| `chat_repository_test.dart` | Chat history persistence | 3 tests |
| `document_management_service_test.dart` | Document ingestion | 3 tests |
| `document_parser_service_test.dart` | Document parsing | 8 tests |
| `environment_service_test.dart` | Environment/flavor detection | 3 tests |
| `query_expansion_service_test.dart` | Query expansion | 3 tests |
| `rag_service_test.dart` | RAG queries | 3 tests |
| `rag_token_manager_test.dart` | Token budget management | 4 tests |
| `reranking_service_test.dart` | LLM reranking | 2 tests |
| `vector_store_test.dart` | Vector database operations | 4 tests |
| `startup_view_test.dart` | Startup UI | 1 test |
| `startup_viewmodel_test.dart` | Startup logic | 2 tests |

### Items Covered by Automated Tests ✅

The following manual verification items have **partial or full automated test coverage**:

#### Section 1: Startup Flow
- [x] **1.1** Loading indicator with "Initializing AI Models..." (`startup_view_test.dart`)
- [x] **1.3** Error handling in startup (`startup_viewmodel_test.dart`)

#### Section 3: Document Management
- [x] **3.2** Document ingestion success flow (`document_management_service_test.dart`)
- [x] **3.3** Multiple format detection: PDF, DOCX, EPUB, Markdown, Plain text (`document_parser_service_test.dart`)
- [x] **3.5** Unsupported format detection (`document_parser_service_test.dart`)
- [x] **3.6** Duplicate detection (`document_management_service_test.dart`)
- [x] **3.8** Document CRUD operations in VectorStore (`vector_store_test.dart`)
- [x] **3.10** Document deletion cascades to vectors (`vector_store_test.dart`)

#### Section 4: Chat Functionality
- [x] **4.2** RAG query flow (`rag_service_test.dart`)
- [x] **4.5** RAG with hybrid search (`vector_store_test.dart`)

#### Section 5: RAG Quality Settings
- [x] **5.1** Query expansion generates variants (`query_expansion_service_test.dart`)
- [x] **5.2** LLM reranking sorts by relevance (`reranking_service_test.dart`)
- [x] **5.5** Semantic vs keyword search weighting (`vector_store_test.dart`)

#### Section 6: Token Management Settings
- [x] **6.2** History budget management (`rag_token_manager_test.dart`)

#### Section 12: Data Persistence
- [x] **12.1** Chat history persistence (`chat_repository_test.dart`)
- [x] **12.4** Token persistence & migration (`auth_token_service_test.dart`)

### Items Requiring Manual Verification ⚠️

The following areas have **limited or no automated tests** and require manual verification:

| Section | Area | Reason |
|---------|------|--------|
| 2 | Model Management | Requires real model downloads (network/hardware dependent) |
| 3.4 | Batch Upload | UI flow not tested |
| 3.7 | Cancellation | Async cancellation hard to unit test |
| 4.3 | Streaming Response | Requires real model for streaming |
| 4.4 | Auto-Scroll Behavior | UI interaction behavior |
| 4.6 | Document Filtering Dialog | Widget interaction |
| 7 | Navigation & UI | Visual verification needed |
| 8 | Error Handling | Network/storage errors hard to simulate |
| 9 | Performance & Edge Cases | Real device testing required |
| 10 | Cross-Platform Testing | Platform-specific behavior |
| 11 | Localization | Visual string verification |
| 12.2 | Settings Persistence | SharedPreferences mocked in tests |
| 12.5 | Model State Persistence | Requires real model state |

---

## Pre-requisites

Before starting manual verification:

- [x] Ensure Flutter SDK is installed and up to date (`flutter doctor`)
- [x] Ensure target device/emulator is available
- [x] Run `flutter pub get` to install dependencies
- [x] Run `flutter analyze` to ensure no lint errors
- [x] Run `flutter test` to ensure all unit tests pass
- [x] Have sample documents ready for testing:
  - [x] PDF file (small, <1MB)
  - [x] PDF file (large, >5MB)
  - [x] DOCX file
  - [x] EPUB file
  - [x] Markdown (.md) file
  - [x] Plain text (.txt) file
  - [x] Unsupported file format (e.g., .xlsx)
- [x] Have a valid HuggingFace access token available (starts with `hf_`)

---

## 1. Startup Flow

### 1.1 First Launch (No Models Downloaded)

- [x] App launches without crash
- [x] Startup screen displays with animated logo
- [x] App title "OfflineSync RAG" displays correctly
- [x] Subtitle "On-device AI with your documents" displays
- [x] Loading indicator with "Initializing AI Models..." message appears
- [x] After initialization, app attempts to download models automatically
- [x] After successful download, app navigates to Chat view

### 1.2 Launch with Downloaded Models

- [x] App launches without crash
- [x] Startup screen appears briefly with loading state
- [x] After model activation, app navigates directly to Chat view
- [x] No error messages appear

### 1.3 Launch with Error State

- [x] When models fail to initialize, error state displays
- [x] Error icon (red) and error message are visible
- [x] "Retry" button is displayed and functional
- [x] "Enter Token" button appears when authentication is required
- [x] Retry button triggers re-initialization flow
- [x] Enter Token button opens token input dialog

---

## 2. Model Management

### 2.1 Model Listing (Settings View)

- [x] Navigate to Settings view
- [x] AI Model Management section displays
- [x] All available models are listed
- [x] Each model shows correct status icon:
  - [x] Green checkmark for downloaded models
  - [x] Cloud icon for not downloaded models
  - [x] Downloading icon for in-progress downloads
    - [ ] Error icon for failed downloads
- [x] Model status label displays correctly (DOWNLOADED, NOT DOWNLOADED, etc.)

### 2.2 Model Download - Inference Model

- [x] Tap download button on an inference model
- [x] Download progress bar appears
- [x] Progress updates smoothly during download
- [x] Upon completion, status changes to "DOWNLOADED"
- [x] Download button disappears for successfully downloaded model
- [ ] Download a inference model and activate it
- [ ] Verify that the activated inference model is used for chat

### 2.3 Model Download - Embedding Model

- [x] Tap download button on embedding model
- [x] If token required, Token Input Dialog appears
- [x] Download progress bar appears after valid token entry
- [x] Upon completion, embedding model status is "DOWNLOADED"
- [ ] Download a embedding model and activate it
- [ ] Verify that the activated embedding model is used for querying and indexing

### 2.4 Model Download - Token Required

- [ ] Attempt to download model requiring authentication
- [ ] Token Input Dialog appears
- [ ] Dialog shows title "Authentication Required"
- [ ] Link to HuggingFace settings is clickable
- [ ] Empty token shows error "Token cannot be empty"
- [ ] Invalid token format (not starting with `hf_`) shows error
- [ ] Valid token saves and download proceeds
- [ ] Cancel button closes dialog without saving

### 2.5 Model Download - Error Handling

- [ ] Simulate network failure during download
- [ ] Download status changes to ERROR
- [ ] Retry/refresh button appears
- [ ] Retry button re-attempts download

---

## 3. Document Management

### 3.1 Document Library - Empty State

- [x] Navigate to Document Library (Settings > Manage Knowledge Base)
- [x] Empty state displays with appropriate icon
- [x] "Add documents" call-to-action is visible
- [x] Floating action button (FAB) to add documents is present

### 3.2 Document Addition - Single Document

- [x] Tap FAB to add document
- [x] File picker opens
- [x] Select a PDF file
- [ ] **Verify ingestion progress card appears** at the top of the document list
- [ ] **Progress card shows document title/filename**
- [ ] **Verify stages display in sequence:**
  - [ ] **"Parsing and chunking..."** stage
    - [ ] Purple icon (description icon)
    - [ ] No progress bar (indeterminate)
  - [ ] **"Generating embeddings..."** stage
    - [ ] Teal icon (sparkle icon)
    - [ ] Linear progress bar appears
    - [ ] Progress bar fills as chunks are processed
    - [ ] **"X/Y chunks" text displays and updates** (e.g., "5/20 chunks")
  - [ ] **"Complete!"** stage
    - [ ] Green icon (check circle)
    - [ ] Shows briefly (2 seconds) before card disappears
- [ ] **Progress card disappears** after completion
- [ ] Document appears in library list below
- [ ] Document shows correct title, format icon, and status badge
- [ ] Green "Ready" status badge displays

**Note:** If Contextual Retrieval is enabled in settings, an additional stage will appear:
- [ ] **"Contextualizing..."** stage (between parsing and embedding)
  - [ ] Orange icon (sparkle icon)
  - [ ] Progress bar with "X/Y chunks" if applicable

### 3.3 Document Addition - Multiple Formats

- [ ] Add DOCX file - verify successful ingestion
- [ ] Add EPUB file - verify successful ingestion
- [ ] Add Markdown file - verify successful ingestion
- [ ] Add Plain text file - verify successful ingestion
- [ ] Each format shows correct format icon in library

### 3.4 Document Addition - Batch Upload

- [ ] Use file picker to select multiple files at once
- [ ] **Verify multiple progress cards appear** stacked vertically at the top
- [ ] **Each progress card shows its own document name**
- [ ] **Each card tracks progress independently:**
  - [ ] Cards may be at different stages simultaneously
  - [ ] Each shows its own progress bar and chunk count
  - [ ] Each completes and disappears independently
- [ ] All successfully ingested documents appear in library

### 3.5 Document Addition - Unsupported Format

- [ ] Attempt to add unsupported file format (e.g., .xlsx)
- [ ] **Progress card appears** showing the file name
- [ ] **"Failed" stage displays:**
  - [ ] Red icon (error icon)
  - [ ] "Failed" label in red
- [ ] **Error dialog appears** with failure message
- [ ] **Progress card remains visible briefly** (2 seconds) then disappears
- [ ] App does not crash

### 3.6 Document Addition - Duplicate Detection

- [ ] Add a document that was already ingested
- [ ] Duplicate detection message appears
- [ ] User is informed document already exists
- [ ] No duplicate entry created in library

### 3.7 Document Addition - Cancellation

- [ ] Start document ingestion
- [ ] Cancel during ingestion process
- [ ] Ingestion stops
- [ ] Document shows "Cancelled" or appropriate status
- [ ] Partial data is cleaned up

### 3.8 Document Detail View

- [ ] Tap on a document in the library
- [ ] Document Detail View opens
- [ ] Document title displays correctly
- [ ] File path displays
- [ ] Format displays correctly
- [ ] Chunk count displays
- [ ] Total characters displays
- [ ] Ingestion date displays correctly formatted
- [ ] Status badge displays
- [ ] Back navigation works

### 3.9 Document Refresh

- [ ] From Document Detail, verify refresh option if available
- [ ] Modify source file on disk
- [ ] Trigger refresh
- [ ] Document re-ingests with updated content
- [ ] Last refreshed timestamp updates

### 3.10 Document Deletion

- [ ] Long-press or swipe on document in library
- [ ] Delete option appears
- [ ] Confirm deletion
- [ ] Document removed from library
- [ ] Associated vectors removed from database
- [ ] Document no longer appears in chat filters

### 3.11 Delete All Documents

- [ ] If "Delete All" option exists, test it
- [ ] Confirmation dialog appears
- [ ] Upon confirmation, all documents removed
- [ ] Library shows empty state

---

## 4. Chat Functionality

### 4.1 Empty Chat State

- [ ] Navigate to Chat view
- [ ] Empty state displays with welcome message
- [ ] Icon and helpful text appear
- [ ] Chat input is visible and functional

### 4.2 Basic Message Sending

- [ ] Type a message in chat input
- [ ] Tap send button
- [ ] User message appears in chat bubble (right-aligned)
- [ ] Timestamp displays correctly
- [ ] AI response appears in chat bubble (left-aligned)
- [ ] Blinking cursor shows during response generation
- [ ] Response completes without errors

### 4.3 Streaming Response

- [ ] Send a query requiring a long response
- [ ] AI response streams token by token
- [ ] Blinking cursor visible during streaming
- [ ] Response completes smoothly
- [ ] No duplicate tokens or content

### 4.4 Auto-Scroll Behavior

- [ ] Send message when near bottom of chat
- [ ] Chat auto-scrolls to show new messages
- [ ] Scroll up to view history
- [ ] Send new message
- [ ] Auto-scroll should NOT jump to bottom (user is viewing history)
- [ ] Manual scroll should restore auto-scroll behavior

### 4.5 RAG with Sources

- [ ] Ensure documents are ingested
- [ ] Ask a question related to ingested document content
- [ ] AI response includes relevant information from documents
- [ ] "Sources" section appears below response
- [ ] Source chips display document titles
- [ ] Tap on source chip opens Document Detail View

### 4.6 Document Filtering (Filter by Documents)

- [ ] Tap filter button in chat input
- [ ] Filter dialog opens
- [ ] All successfully ingested documents listed
- [ ] Failed documents NOT listed
- [ ] Select one or more documents
- [ ] Confirm filter selection
- [ ] Filter indicator badge appears on filter button
- [ ] Send message - RAG uses only selected documents
- [ ] Sources in response are from filtered documents only
- [ ] Clear all filters
- [ ] Filter indicator badge disappears

### 4.7 File Attachment from Chat

- [ ] Tap attach button in chat input
- [ ] File picker opens
- [ ] Select a document
- [ ] Document ingestion begins
- [ ] Upon completion, document available for RAG

### 4.8 Navigate to Settings from Chat

- [ ] Tap settings icon/menu in chat view
- [ ] Settings view opens
- [ ] Back navigation returns to chat
- [ ] Chat history preserved

### 4.9 Send on Enter

- [ ] Type message in chat input
- [ ] Press Enter/Return key
- [ ] Message sends without needing to tap button
- [ ] Focus returns to input field

### 4.10 Empty Message Prevention

- [ ] Attempt to send empty message
- [ ] Send button disabled or message not sent
- [ ] No AI response triggered

---

## 5. RAG Quality Settings

### 5.1 Query Expansion Toggle

- [ ] Navigate to Settings > RAG Quality Settings
- [ ] Toggle "Query Expansion" ON
- [ ] Return to chat, ask a question
- [ ] Response potentially improved (may take longer)
- [ ] Toggle OFF and verify behavior reverts

### 5.2 LLM Reranking Toggle

- [ ] Toggle "LLM Reranking" ON
- [ ] Return to chat, ask a question
- [ ] Response should prioritize more relevant sources
- [ ] Toggle OFF and verify behavior reverts

### 5.3 Contextual Retrieval Toggle

- [ ] Toggle "Contextual Retrieval" ON
- [ ] New documents ingested will have context added to chunks
- [ ] Toggle OFF for standard ingestion

### 5.4 Chunk Overlap Slider

- [ ] Adjust "Chunk Overlap" slider (0% to 30%)
- [ ] Slider label updates with current value
- [ ] Value persists after leaving and returning to Settings
- [ ] Note: affects new document ingestion

### 5.5 Semantic vs Keyword Weight Slider

- [ ] Adjust "Semantic vs Keyword" slider (0% to 100%)
- [ ] Slider label updates with current value
- [ ] 100% = pure semantic search
- [ ] 0% = pure keyword search
- [ ] Test different values and observe search behavior differences

---

## 6. Token Management Settings

### 6.1 Search Top K Slider

- [ ] Navigate to Settings > Token Management
- [ ] Adjust "Search Top K" slider (1 to 5)
- [ ] Lower values = fewer context chunks
- [ ] Higher values = more context but more tokens
- [ ] Value persists between app sessions

### 6.2 Max History Messages Slider

- [ ] Adjust "Max History Messages" slider (0 to 5)
- [ ] 0 = no conversation history included
- [ ] Higher values include more previous messages
- [ ] Test with conversation history in chat

### 6.3 Max Tokens Slider

- [ ] Adjust "Max Tokens" slider (512 to 8192)
- [ ] Custom value shows "(Custom)" label
- [ ] Setting to model default removes custom label
- [ ] Value affects model context window limit

---

## 7. Navigation & UI

### 7.1 Navigation Flow

- [ ] Startup → Chat (when models ready)
- [ ] Startup → Settings (when models need download)
- [ ] Chat → Settings (via settings button)
- [ ] Settings → Document Library (via Manage Knowledge Base)
- [ ] Document Library → Document Detail (tap document)
- [ ] Back navigation works correctly in all views

### 7.2 App Bar Behavior

- [ ] App bar shows correct title for each view
- [ ] Back button appears when appropriate
- [ ] Scroll causes app bar elevation change (Material 3)

### 7.3 Theme & Visual Design

- [ ] App uses consistent color scheme
- [ ] Dark mode: verify all elements visible
- [ ] Light mode: verify all elements visible
- [ ] Gradients and shadows render correctly
- [ ] Icons are appropriate and visible

### 7.4 Responsive Layout

- [ ] Test on phone (portrait)
- [ ] Test on phone (landscape)
- [ ] Test on tablet (portrait)
- [ ] Test on tablet (landscape)
- [ ] Chat bubbles responsive to screen width
- [ ] Dialogs properly sized

---

## 8. Error Handling

### 8.1 Network Errors

- [ ] Enable airplane mode
- [ ] Attempt model download
- [ ] Appropriate error message displays
- [ ] Retry option available
- [ ] Disable airplane mode, retry succeeds

### 8.2 Storage Errors

- [ ] Fill device storage (or simulate)
- [ ] Attempt document ingestion
- [ ] Error handled gracefully
- [ ] User informed of issue

### 8.3 Model Not Ready

- [ ] Attempt to chat before models downloaded
- [ ] Appropriate message or redirect to settings
- [ ] No app crash

### 8.4 Invalid Document

- [ ] Select corrupt or invalid PDF
- [ ] Error message displays
- [ ] App recovers gracefully
- [ ] Other documents can still be added

### 8.5 Token Limit Exceeded

- [ ] Add very large documents
- [ ] Ask questions requiring all context
- [ ] App handles token limits gracefully
- [ ] Response may indicate context was truncated
- [ ] No crash or hang

### 8.6 Empty Response Handling

- [ ] Ask a question unrelated to documents
- [ ] If no relevant context found, response indicates this
- [ ] No crash or empty bubble

---

## 9. Performance & Edge Cases

### 9.1 Large Document Handling

- [ ] Add PDF > 5MB
- [ ] Ingestion completes (may take time)
- [ ] Progress updates showing X/Y chunks
- [ ] No UI freeze during ingestion
- [ ] Document usable for RAG after ingestion

### 9.2 Many Documents

- [ ] Add 10+ documents
- [ ] Document library scrolls smoothly
- [ ] Chat filtering dialog lists all documents
- [ ] Search still performs adequately

### 9.3 Long Conversation

- [ ] Have 20+ message exchanges
- [ ] Chat scrolls smoothly
- [ ] History management working (older messages may not be included in context)
- [ ] No memory issues

### 9.4 Rapid Interactions

- [ ] Send multiple messages quickly
- [ ] App handles queue appropriately
- [ ] No duplicate messages or responses
- [ ] No crash

### 9.5 App Lifecycle

- [ ] Send message, minimize app
- [ ] Return to app - chat preserved
- [ ] Rotate device during response generation
- [ ] App handles rotation gracefully

### 9.6 Database Optimization

- [ ] If "Optimize Database" feature exists, test it
- [ ] Operation completes without error
- [ ] App continues to function normally

---

## 10. Cross-Platform Testing

### 10.1 Android

- [ ] Install on Android device/emulator
- [ ] All features work as expected
- [ ] File picker works correctly
- [ ] Secure storage (token) works
- [ ] Model download/activation works

### 10.2 iOS

- [ ] Install on iOS device/simulator
- [ ] All features work as expected
- [ ] File picker works correctly
- [ ] Secure storage (Keychain) works
- [ ] Model download/activation works

### 10.3 Web

- [ ] Run on Chrome/Edge
- [ ] Note: some features may be limited on web
- [ ] Vector store SQLite works via WebAssembly
- [ ] File picker works correctly
- [ ] Identify any web-specific limitations

### 10.4 Linux/macOS/Windows

- [ ] Run on desktop platform
- [ ] Window resizing works
- [ ] File picker works correctly
- [ ] All core features functional

---

## 11. Localization

### 11.1 English Locale

- [ ] Set device to English
- [ ] All UI strings display correctly
- [ ] No placeholder text visible
- [ ] Date/time formatting correct

### 11.2 Alternative Locales

- [ ] If other locales supported, switch device language
- [ ] UI strings update appropriately
- [ ] Fallback to English for missing translations

### 11.3 RTL Support

- [ ] If RTL languages supported, test layout
- [ ] Text alignment correct
- [ ] UI elements positioned correctly

---

## 12. Data Persistence

### 12.1 Chat History Persistence

- [ ] Have a conversation
- [ ] Force close app
- [ ] Reopen app
- [ ] Chat history restored

### 12.2 Settings Persistence

- [ ] Modify RAG quality settings
- [ ] Modify token management settings
- [ ] Force close app
- [ ] Reopen app
- [ ] All settings preserved

### 12.3 Document Library Persistence

- [ ] Add documents
- [ ] Force close app
- [ ] Reopen app
- [ ] Documents still listed
- [ ] Documents usable for RAG

### 12.4 Token Persistence

- [ ] Enter HuggingFace token
- [ ] Force close app
- [ ] Reopen app
- [ ] Token still available (model downloads work)

### 12.5 Model State Persistence

- [ ] Download models
- [ ] Force close app
- [ ] Reopen app
- [ ] Models still show as downloaded
- [ ] No re-download required

---

## 📝 Test Execution Log

| Test ID | Description | Tester | Date | Pass/Fail | Notes |
|---------|-------------|--------|------|-----------|-------|
| 1.1 | First Launch | | | | |
| 1.2 | Launch with Models | | | | |
| ... | ... | | | | |

---

## 🐛 Bug Tracking

| Bug ID | Test Case | Description | Severity | Status |
|--------|-----------|-------------|----------|--------|
| | | | | |

---

## ✅ Sign-off

| Role | Name | Date | Signature |
|------|------|------|-----------|
| QA Lead | | | |
| Developer | | | |
| Product Owner | | | |

---

## Revision History

| Version | Date | Author | Changes |
|---------|------|--------|---------|
| 1.0 | 2026-01-20 | Antigravity | Initial version |
