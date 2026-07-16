# Licensing Notes

## Syncfusion PDF dependency

- Package in use: `syncfusion_flutter_pdf ^33.2.13` from [pubspec.yaml](/media/limcheekin/My Passport/ws/rag.wtf/offline_sync/pubspec.yaml:36)
- Current code use: [lib/services/document_parser_service.dart](/media/limcheekin/My Passport/ws/rag.wtf/offline_sync/lib/services/document_parser_service.dart:8)
- Current repository evidence:
  - `rg "registerLicense|Syncfusion|syncfusion"` shows no `registerLicense` call in app code.
  - [docs/document_mgmt_implementation_plan.md](/media/limcheekin/My Passport/ws/rag.wtf/offline_sync/docs/document_mgmt_implementation_plan.md:8) states the package requires a community or commercial license.
  - [docs/production-audit.md](/media/limcheekin/My Passport/ws/rag.wtf/offline_sync/docs/production-audit.md:274) records this as a legal risk, not a runtime failure.

## Decision status

Maintainer decision required. This repository does not currently contain enough local information to determine whether the project is eligible for Syncfusion's Community License, and no commercial-license registration path is implemented.

## Required follow-up

Choose one of these before shipping:

1. Confirm Community License eligibility and record the basis in this file.
2. Acquire a commercial license and document where license registration is wired into app startup.
3. Replace `syncfusion_flutter_pdf` with a permissively licensed PDF parsing approach.

Until that decision is made, treat Syncfusion usage as an unresolved release risk.
